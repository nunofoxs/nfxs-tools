
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

Add-Type -Name Input -Namespace NFX -MemberDefinition @"
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
"@
function Set-CueBanner($TextBox, $Text) {
	$EM_SETCUEBANNER = 0x1501
	try { [void][NFX.Input]::SendMessage($TextBox.Handle, $EM_SETCUEBANNER, [IntPtr]1, $Text) } catch {}
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

function Test-ValidAddress($Value) {
	if (-not $Value -or $Value.Length -gt 100 -or $Value -match '\s') {
		return $false
	}
	return ($Value -match ':\d{1,5}$') -or ($Value -match 'cfx\.re/join/')
}

$Games = @{
	"FiveM" = @{
		DefaultAddress = ""
	}
	"RedM" = @{
		DefaultAddress = ""
	}
}

function Get-HostAndPort($Address) {
	if (-not (Test-ValidAddress $Address)) {
		return $null
	}
	if ($Address -match '^([^:]+):(\d{1,5})$') {
		return [PSCustomObject]@{ HostName = $Matches[1]; Port = $Matches[2] }
	}
	return $null
}

function Send-SinglePing($TargetHost, $TimeoutMs = 1000) {
	$Pinger = $null
	try {
		$Pinger = New-Object System.Net.NetworkInformation.Ping
		$Reply = $Pinger.Send($TargetHost, $TimeoutMs)
		if ($Reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
			return $Reply.RoundtripTime
		}
	} catch {
	} finally {
		if ($Pinger) { $Pinger.Dispose() }
	}
	return $null
}

function Test-InternetActive {
	for ($i = 0; $i -lt 2; $i++) {
		if ((Send-SinglePing "1.1.1.1" 1500) -ne $null) {
			return $true
		}
	}
	return $false
}

function Get-DNSInfo {
	$Result = [PSCustomObject]@{ Working = $false; ServerUsed = $null; ResolutionMs = $null }
	try {
		$DnsConfig = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
			Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -First 1
		if ($DnsConfig) {
			$Result.ServerUsed = $DnsConfig.ServerAddresses[0]
		}
	} catch {
	}
	try {
		$Sw = [System.Diagnostics.Stopwatch]::StartNew()
		$Addresses = [System.Net.Dns]::GetHostAddresses("www.google.com")
		$Sw.Stop()
		if ($Addresses.Count -gt 0) {
			$Result.Working = $true
			$Result.ResolutionMs = $Sw.ElapsedMilliseconds
		}
	} catch {
	}
	return $Result
}

function Get-LocalNetworkInfo {
	try {
		$Config = Get-NetIPConfiguration -ErrorAction Stop |
			Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
			Select-Object -First 1
		if (-not $Config) {
			return $null
		}
		$Adapter = Get-NetAdapter -InterfaceIndex $Config.InterfaceIndex -ErrorAction SilentlyContinue
		return [PSCustomObject]@{
			LocalIP       = $Config.IPv4Address.IPAddress
			Gateway       = $Config.IPv4DefaultGateway.NextHop
			InterfaceName = $Config.InterfaceAlias
			LinkSpeed     = if ($Adapter) { $Adapter.LinkSpeed } else { $null }
		}
	} catch {
		return $null
	}
}

function Get-PublicIP {
	try {
		$Response = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3 -ErrorAction Stop
		$Value = ([string]$Response).Trim()
		if ($Value) {
			return $Value
		}
	} catch {
	}
	return $null
}

function Test-PingStats($TargetHost, $Attempts = 4, $TimeoutMs = 1000) {
	$Times = @()
	for ($i = 0; $i -lt $Attempts; $i++) {
		$Ms = Send-SinglePing $TargetHost $TimeoutMs
		if ($Ms -ne $null) { $Times += $Ms }
	}
	$Received = $Times.Count
	$LossPercent = [Math]::Round((($Attempts - $Received) / $Attempts) * 100)
	$MinMs = $null; $AvgMs = $null; $MaxMs = $null; $JitterMs = $null
	if ($Received -gt 0) {
		$MinMs = ($Times | Measure-Object -Minimum).Minimum
		$MaxMs = ($Times | Measure-Object -Maximum).Maximum
		$AvgMs = [Math]::Round(($Times | Measure-Object -Average).Average)
		if ($Times.Count -ge 2) {
			$Diffs = for ($i = 1; $i -lt $Times.Count; $i++) { [Math]::Abs($Times[$i] - $Times[$i - 1]) }
			$JitterMs = [Math]::Round(($Diffs | Measure-Object -Average).Average)
		}
	}
	return [PSCustomObject]@{
		Reachable   = ($Received -gt 0)
		Sent        = $Attempts
		Received    = $Received
		LossPercent = $LossPercent
		MinMs       = $MinMs
		AvgMs       = $AvgMs
		MaxMs       = $MaxMs
		JitterMs    = $JitterMs
	}
}

function Test-FiveMEndpoint($TargetHost, $Port) {
	$Result = [PSCustomObject]@{
		HttpStatus        = $null
		ResponseMs        = $null
		FXServerConfirmed = $false
		ServerName        = $null
	}
	$InfoUri = "http://${TargetHost}:${Port}/info.json"
	try {
		$Sw = [System.Diagnostics.Stopwatch]::StartNew()
		$Response = Invoke-WebRequest -Uri $InfoUri -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
		$Sw.Stop()
		$Result.HttpStatus = [int]$Response.StatusCode
		$Result.ResponseMs = $Sw.ElapsedMilliseconds
		if ($Response.StatusCode -eq 200) {
			$RawText = if ($Response.Content -is [byte[]]) {
				[System.Text.Encoding]::UTF8.GetString($Response.Content)
			} else {
				[string]$Response.Content
			}
			$Json = $RawText | ConvertFrom-Json -ErrorAction Stop
			if ($Json.server -and ($Json.server -match '^FXServer')) {
				$Result.FXServerConfirmed = $true
				if ($Json.vars -and $Json.vars.sv_projectName) {
					$Result.ServerName = $Json.vars.sv_projectName
				}
			}
		}
	} catch {
		if ($_.Exception.Response) {
			try { $Result.HttpStatus = [int]$_.Exception.Response.StatusCode } catch {}
		}
	}

	return $Result
}

function Get-LatencyLevel($Ms) {
	$S = $Strings[$CurrentLang]
	if ($Ms -lt 50) {
		return [PSCustomObject]@{ Title = $S.LatencyExcellentTitle; ColorKey = "Success" }
	} elseif ($Ms -lt 100) {
		return [PSCustomObject]@{ Title = $S.LatencyGoodTitle; ColorKey = "Success" }
	} elseif ($Ms -lt 150) {
		return [PSCustomObject]@{ Title = $S.LatencyOkTitle; ColorKey = "Warning" }
	} else {
		return [PSCustomObject]@{ Title = $S.LatencyHighTitle; ColorKey = "Alert" }
	}
}

$SettingsDir  = Join-Path $env:APPDATA "NFXS-Connection"
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
		Description               = "Verifique se a sua conexão está boa pra jogar no FiveM ou RedM."
		GameLabel                 = "Jogo"
		AddressLabel              = "Endereço do servidor (opcional)"
		AddressPlaceholder        = "ex: 192.168.0.1:30120"
		CheckingLabel             = "Verificando..."
		InternetLabel             = "Internet"
		InternetOk                = "Ativa"
		InternetDown              = "Sem conexão"
		DNSLabel                  = "DNS"
		DNSOk                     = "Funcionando"
		DNSDown                   = "Não funcionando"
		LatencyNoAddressTitle     = "Endereço não configurado"
		LatencyNoAddressDesc      = "Preencha o endereço do servidor acima pra medir a latência."
		LatencyInvalidFormatTitle = "Formato não suportado"
		LatencyInvalidFormatDesc  = "Esse formato de endereço não dá pra testar diretamente - use o formato IP:porta."
		LatencyUnreachableTitle   = "Sem resposta ao ping"
		LatencyUnreachableDesc    = "Muitos servidores bloqueiam ping por segurança mesmo estando online - isso não significa que o servidor está fora do ar. Se você consegue jogar normalmente, pode ignorar."
		LatencyExcellentTitle     = "Latência ótima"
		LatencyGoodTitle          = "Latência boa"
		LatencyOkTitle            = "Latência aceitável"
		LatencyHighTitle          = "Latência alta"
		LatencyDescFormat         = "{0} ms de ping · {1}% de perda em {2} tentativas."
		EndpointAccessibleTitle   = "Endpoint FiveM acessível"
		EndpointConfirmedDescFormat = "FXServer confirmado: {0} ms"
		EndpointServerNameFormat  = "Nome do Servidor: {0}"
		EndpointNotAccessibleTitle = "Endpoint FiveM não respondeu"
		EndpointUnreachableDesc   = "Não conseguimos alcançar esse endereço:porta pela web - o servidor pode estar offline ou bloqueando esse tipo de acesso."
		EndpointNotFXServerDesc   = "Recebemos resposta desse endereço, mas não parece ser um servidor FiveM/RedM."
		EndpointRateLimitedTitle  = "Limite de requisições atingido"
		EndpointRateLimitedDesc   = "O servidor limitou nossa consulta por segurança - tente novamente em alguns instantes."
		DiagnosisHeader           = "Diagnóstico"
		DiagInternetDownText      = "Não foi possível confirmar conectividade geral com a internet."
		DiagGatewayOkText         = "Sua rede local apresenta latência normal."
		DiagGatewayWarnText       = "Sua rede local (até o roteador) apresenta latência ou perda fora do normal - pode ser Wi-Fi, cabo ou o próprio roteador."
		DiagGatewayUnreachableText = "O roteador local não respondeu ao teste de latência (comum em alguns modelos, não indica problema)."
		DiagGatewayUnknownText    = "Não foi possível determinar a latência até o roteador local."
		DiagDnsOkText             = "DNS está funcionando normalmente."
		DiagDnsSlowText           = "DNS está funcionando, mas a resolução de nomes está lenta."
		DiagDnsDownText           = "DNS não conseguiu resolver nomes durante o teste."
		DiagNoTargetText          = "Configure o endereço do servidor acima pra incluir latência, perda de pacotes e o endpoint no diagnóstico."
		DiagLossOkText            = "Não foi detectada perda de pacotes no teste realizado."
		DiagLossWarnFormat        = "Foi detectada perda de pacotes no caminho até o servidor ({0}%)."
		DiagLossUnknownText       = "Não foi possível medir perda de pacotes via ping (o servidor pode estar bloqueando ICMP por segurança)."
		DiagJitterOkText          = "Jitter (variação de latência) até o servidor dentro do normal."
		DiagJitterWarnText        = "Jitter (variação de latência) até o servidor está alto, o que pode causar oscilação durante o jogo."
		DiagEndpointHighVsIcmpText = "A latência até o endpoint do FiveM está significativamente acima da latência da sua conexão externa."
		DiagCauseUnknownText      = "Não foi possível determinar se a causa está no ISP, na rota ou no destino."
		DiagEndpointConsistentText = "O tempo de resposta do endpoint do FiveM é consistente com a latência da sua conexão até esse destino."
		DiagEndpointFastNoBaselineText = "O endpoint do FiveM respondeu em tempo considerado normal."
		DiagEndpointModerateNoBaselineText = "O tempo de resposta do endpoint está moderado, mas sem uma referência de latência local pra comparar."
		DiagEndpointSlowNoBaselineText = "O tempo de resposta do endpoint do FiveM está alto."
		DiagEndpointUnreachableText = "O endpoint desse endereço não respondeu - pode ser a porta configurada, o servidor estar offline, ou um bloqueio específico nessa porta."
		DiagEndpointUnreachableButNetworkOkText = "Sua rede consegue alcançar esse host normalmente (ping respondeu), o que sugere que o problema não é geral da sua conexão."
		DiagEndpointNotFXServerText = "Recebemos uma resposta desse endereço, mas ela não parece vir de um servidor FiveM/RedM - confira se a porta está correta."
		DiagEndpointRateLimitedText = "O servidor limitou nossa consulta por segurança - não foi possível confirmar o endpoint nesta tentativa."
		RefreshButton             = "Verificar novamente"
		CloseButton               = "Fechar"
		ThemeButtonLight          = "Modo Claro"
		ThemeButtonDark           = "Modo Escuro"
		UpdateAvailableFormat     = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk                  = "Você está com a versão mais recente."
		NewsHeader                = "Obrigado por usar nosso app, acesse:"
		FreeLabel                 = "Produto gratuito disponibilizado por NunoFoxs"
	}
	"en" = @{
		Description               = "Check if your connection is good enough to play FiveM or RedM."
		GameLabel                 = "Game"
		AddressLabel              = "Server address (optional)"
		AddressPlaceholder        = "e.g. 192.168.0.1:30120"
		CheckingLabel             = "Checking..."
		InternetLabel             = "Internet"
		InternetOk                = "Active"
		InternetDown              = "No connection"
		DNSLabel                  = "DNS"
		DNSOk                     = "Working"
		DNSDown                   = "Not working"
		LatencyNoAddressTitle     = "Address not configured"
		LatencyNoAddressDesc      = "Fill in the server address above to measure latency."
		LatencyInvalidFormatTitle = "Format not supported"
		LatencyInvalidFormatDesc  = "This address format can't be tested directly - use the IP:port format."
		LatencyUnreachableTitle   = "No ping response"
		LatencyUnreachableDesc    = "Many servers block ping for security even while online - this doesn't mean the server is down. If you can play normally, you can ignore this."
		LatencyExcellentTitle     = "Excellent latency"
		LatencyGoodTitle          = "Good latency"
		LatencyOkTitle            = "Acceptable latency"
		LatencyHighTitle          = "High latency"
		LatencyDescFormat         = "{0} ms ping · {1}% loss over {2} attempts."
		EndpointAccessibleTitle   = "FiveM endpoint reachable"
		EndpointConfirmedDescFormat = "FXServer confirmed: {0} ms"
		EndpointServerNameFormat  = "Server Name: {0}"
		EndpointNotAccessibleTitle = "FiveM endpoint didn't respond"
		EndpointUnreachableDesc   = "We couldn't reach that address:port over the web - the server may be offline or blocking this kind of access."
		EndpointNotFXServerDesc   = "We got a response from that address, but it doesn't look like a FiveM/RedM server."
		EndpointRateLimitedTitle  = "Request limit reached"
		EndpointRateLimitedDesc   = "The server rate-limited our request for security - try again in a moment."
		DiagnosisHeader           = "Diagnosis"
		DiagInternetDownText      = "We couldn't confirm general internet connectivity."
		DiagGatewayOkText         = "Your local network shows normal latency."
		DiagGatewayWarnText       = "Your local network (up to the router) shows latency or loss outside the normal range - could be Wi-Fi, cabling, or the router itself."
		DiagGatewayUnreachableText = "The local router didn't respond to the latency test (common on some models, not necessarily a problem)."
		DiagGatewayUnknownText    = "We couldn't determine latency to the local router."
		DiagDnsOkText             = "DNS is working normally."
		DiagDnsSlowText           = "DNS is working, but name resolution is slow."
		DiagDnsDownText           = "DNS couldn't resolve names during the test."
		DiagNoTargetText          = "Fill in the server address above to include latency, packet loss, and the endpoint in the diagnosis."
		DiagLossOkText            = "No packet loss was detected in this test."
		DiagLossWarnFormat        = "Packet loss was detected on the path to the server ({0}%)."
		DiagLossUnknownText       = "We couldn't measure packet loss via ping (the server may be blocking ICMP for security)."
		DiagJitterOkText          = "Jitter (latency variation) to the server is within normal range."
		DiagJitterWarnText        = "Jitter (latency variation) to the server is high, which can cause instability during gameplay."
		DiagEndpointHighVsIcmpText = "Latency to the FiveM endpoint is significantly higher than your external connection's latency."
		DiagCauseUnknownText      = "We couldn't determine whether the cause is your ISP, the route, or the destination."
		DiagEndpointConsistentText = "The FiveM endpoint's response time is consistent with your connection's latency to that destination."
		DiagEndpointFastNoBaselineText = "The FiveM endpoint responded within a normal time."
		DiagEndpointModerateNoBaselineText = "The endpoint's response time is moderate, but there's no local latency reference to compare it to."
		DiagEndpointSlowNoBaselineText = "The FiveM endpoint's response time is high."
		DiagEndpointUnreachableText = "The endpoint at that address didn't respond - could be the configured port, the server being offline, or a block specific to that port."
		DiagEndpointUnreachableButNetworkOkText = "Your network can reach that host normally (ping responded), which suggests the problem isn't general to your connection."
		DiagEndpointNotFXServerText = "We got a response from that address, but it doesn't look like it came from a FiveM/RedM server - check whether the port is correct."
		DiagEndpointRateLimitedText = "The server rate-limited our request for security - we couldn't confirm the endpoint on this attempt."
		RefreshButton             = "Check again"
		CloseButton               = "Close"
		ThemeButtonLight          = "Light Mode"
		ThemeButtonDark           = "Dark Mode"
		UpdateAvailableFormat     = "New version available (v{0}) - click here"
		UpdateOk                  = "You have the latest version."
		NewsHeader                = "Thanks for using our app, check out:"
		FreeLabel                 = "Free product provided by NunoFoxs"
	}
	"es" = @{
		Description               = "Verifica si tu conexión es buena para jugar FiveM o RedM."
		GameLabel                 = "Juego"
		AddressLabel              = "Dirección del servidor (opcional)"
		AddressPlaceholder        = "ej: 192.168.0.1:30120"
		CheckingLabel             = "Verificando..."
		InternetLabel             = "Internet"
		InternetOk                = "Activa"
		InternetDown              = "Sin conexión"
		DNSLabel                  = "DNS"
		DNSOk                     = "Funcionando"
		DNSDown                   = "No funciona"
		LatencyNoAddressTitle     = "Dirección no configurada"
		LatencyNoAddressDesc      = "Completa la dirección del servidor arriba para medir la latencia."
		LatencyInvalidFormatTitle = "Formato no compatible"
		LatencyInvalidFormatDesc  = "Este formato de dirección no se puede probar directamente - usa el formato IP:puerto."
		LatencyUnreachableTitle   = "Sin respuesta al ping"
		LatencyUnreachableDesc    = "Muchos servidores bloquean el ping por seguridad aunque estén online - esto no significa que el servidor esté caído. Si puedes jugar normalmente, puedes ignorar esto."
		LatencyExcellentTitle     = "Latencia excelente"
		LatencyGoodTitle          = "Latencia buena"
		LatencyOkTitle            = "Latencia aceptable"
		LatencyHighTitle          = "Latencia alta"
		LatencyDescFormat         = "{0} ms de ping · {1}% de pérdida en {2} intentos."
		EndpointAccessibleTitle   = "Endpoint FiveM accesible"
		EndpointConfirmedDescFormat = "FXServer confirmado: {0} ms"
		EndpointServerNameFormat  = "Nombre del Servidor: {0}"
		EndpointNotAccessibleTitle = "El endpoint FiveM no respondió"
		EndpointUnreachableDesc   = "No pudimos alcanzar esa dirección:puerto por la web - el servidor puede estar offline o bloqueando este tipo de acceso."
		EndpointNotFXServerDesc   = "Recibimos respuesta de esa dirección, pero no parece ser un servidor FiveM/RedM."
		EndpointRateLimitedTitle  = "Límite de solicitudes alcanzado"
		EndpointRateLimitedDesc   = "El servidor limitó nuestra consulta por seguridad - intenta de nuevo en unos instantes."
		DiagnosisHeader           = "Diagnóstico"
		DiagInternetDownText      = "No pudimos confirmar conectividad general con internet."
		DiagGatewayOkText         = "Tu red local muestra latencia normal."
		DiagGatewayWarnText       = "Tu red local (hasta el router) muestra latencia o pérdida fuera de lo normal - puede ser Wi-Fi, cable o el propio router."
		DiagGatewayUnreachableText = "El router local no respondió a la prueba de latencia (común en algunos modelos, no indica un problema)."
		DiagGatewayUnknownText    = "No pudimos determinar la latencia hasta el router local."
		DiagDnsOkText             = "El DNS está funcionando normalmente."
		DiagDnsSlowText           = "El DNS está funcionando, pero la resolución de nombres está lenta."
		DiagDnsDownText           = "El DNS no pudo resolver nombres durante la prueba."
		DiagNoTargetText          = "Completa la dirección del servidor arriba para incluir latencia, pérdida de paquetes y el endpoint en el diagnóstico."
		DiagLossOkText            = "No se detectó pérdida de paquetes en la prueba realizada."
		DiagLossWarnFormat        = "Se detectó pérdida de paquetes en el camino hasta el servidor ({0}%)."
		DiagLossUnknownText       = "No pudimos medir la pérdida de paquetes por ping (el servidor puede estar bloqueando ICMP por seguridad)."
		DiagJitterOkText          = "El jitter (variación de latencia) hasta el servidor está dentro de lo normal."
		DiagJitterWarnText        = "El jitter (variación de latencia) hasta el servidor está alto, lo que puede causar inestabilidad durante el juego."
		DiagEndpointHighVsIcmpText = "La latencia hasta el endpoint de FiveM está significativamente por encima de la latencia de tu conexión externa."
		DiagCauseUnknownText      = "No pudimos determinar si la causa está en tu ISP, en la ruta o en el destino."
		DiagEndpointConsistentText = "El tiempo de respuesta del endpoint de FiveM es consistente con la latencia de tu conexión hasta ese destino."
		DiagEndpointFastNoBaselineText = "El endpoint de FiveM respondió en un tiempo considerado normal."
		DiagEndpointModerateNoBaselineText = "El tiempo de respuesta del endpoint es moderado, pero no hay una referencia de latencia local para comparar."
		DiagEndpointSlowNoBaselineText = "El tiempo de respuesta del endpoint de FiveM está alto."
		DiagEndpointUnreachableText = "El endpoint de esa dirección no respondió - puede ser el puerto configurado, el servidor estar offline, o un bloqueo específico de ese puerto."
		DiagEndpointUnreachableButNetworkOkText = "Tu red puede alcanzar ese host normalmente (el ping respondió), lo que sugiere que el problema no es general de tu conexión."
		DiagEndpointNotFXServerText = "Recibimos una respuesta de esa dirección, pero no parece venir de un servidor FiveM/RedM - revisa si el puerto es correcto."
		DiagEndpointRateLimitedText = "El servidor limitó nuestra consulta por seguridad - no pudimos confirmar el endpoint en este intento."
		RefreshButton             = "Verificar de nuevo"
		CloseButton               = "Cerrar"
		ThemeButtonLight          = "Modo Claro"
		ThemeButtonDark           = "Modo Oscuro"
		UpdateAvailableFormat     = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk                  = "Tienes la versión más reciente."
		NewsHeader                = "Gracias por usar nuestra app, visita:"
		FreeLabel                 = "Producto gratuito ofrecido por NunoFoxs"
	}
	"de" = @{
		Description               = "Prüfe, ob deine Verbindung gut genug ist, um FiveM oder RedM zu spielen."
		GameLabel                 = "Spiel"
		AddressLabel              = "Serveradresse (optional)"
		AddressPlaceholder        = "z.B. 192.168.0.1:30120"
		CheckingLabel             = "Wird geprüft..."
		InternetLabel             = "Internet"
		InternetOk                = "Aktiv"
		InternetDown              = "Keine Verbindung"
		DNSLabel                  = "DNS"
		DNSOk                     = "Funktioniert"
		DNSDown                   = "Funktioniert nicht"
		LatencyNoAddressTitle     = "Adresse nicht konfiguriert"
		LatencyNoAddressDesc      = "Gib oben die Serveradresse ein, um die Latenz zu messen."
		LatencyInvalidFormatTitle = "Format nicht unterstützt"
		LatencyInvalidFormatDesc  = "Dieses Adressformat kann nicht direkt getestet werden - verwende das Format IP:Port."
		LatencyUnreachableTitle   = "Keine Ping-Antwort"
		LatencyUnreachableDesc    = "Viele Server blockieren Ping aus Sicherheitsgründen, auch wenn sie online sind - das bedeutet nicht, dass der Server offline ist. Wenn du normal spielen kannst, kannst du das ignorieren."
		LatencyExcellentTitle     = "Ausgezeichnete Latenz"
		LatencyGoodTitle          = "Gute Latenz"
		LatencyOkTitle            = "Akzeptable Latenz"
		LatencyHighTitle          = "Hohe Latenz"
		LatencyDescFormat         = "{0} ms Ping · {1}% Verlust bei {2} Versuchen."
		EndpointAccessibleTitle   = "FiveM-Endpoint erreichbar"
		EndpointConfirmedDescFormat = "FXServer bestätigt: {0} ms"
		EndpointServerNameFormat  = "Servername: {0}"
		EndpointNotAccessibleTitle = "FiveM-Endpoint hat nicht geantwortet"
		EndpointUnreachableDesc   = "Wir konnten diese Adresse:Port über das Web nicht erreichen - der Server könnte offline sein oder diese Art von Zugriff blockieren."
		EndpointNotFXServerDesc   = "Wir haben eine Antwort von dieser Adresse erhalten, aber sie sieht nicht wie ein FiveM/RedM-Server aus."
		EndpointRateLimitedTitle  = "Anfragelimit erreicht"
		EndpointRateLimitedDesc   = "Der Server hat unsere Anfrage aus Sicherheitsgründen begrenzt - versuche es in einem Moment erneut."
		DiagnosisHeader           = "Diagnose"
		DiagInternetDownText      = "Wir konnten die allgemeine Internetverbindung nicht bestätigen."
		DiagGatewayOkText         = "Dein lokales Netzwerk zeigt normale Latenz."
		DiagGatewayWarnText       = "Dein lokales Netzwerk (bis zum Router) zeigt Latenz oder Verlust außerhalb des Normalbereichs - könnte WLAN, Kabel oder der Router selbst sein."
		DiagGatewayUnreachableText = "Der lokale Router hat auf den Latenztest nicht geantwortet (bei manchen Modellen üblich, kein zwingendes Problem)."
		DiagGatewayUnknownText    = "Wir konnten die Latenz zum lokalen Router nicht ermitteln."
		DiagDnsOkText             = "DNS funktioniert normal."
		DiagDnsSlowText           = "DNS funktioniert, aber die Namensauflösung ist langsam."
		DiagDnsDownText           = "DNS konnte während des Tests keine Namen auflösen."
		DiagNoTargetText          = "Gib oben die Serveradresse ein, um Latenz, Paketverlust und den Endpoint in die Diagnose einzubeziehen."
		DiagLossOkText            = "In diesem Test wurde kein Paketverlust festgestellt."
		DiagLossWarnFormat        = "Auf dem Weg zum Server wurde Paketverlust festgestellt ({0}%)."
		DiagLossUnknownText       = "Wir konnten den Paketverlust per Ping nicht messen (der Server blockiert ICMP möglicherweise aus Sicherheitsgründen)."
		DiagJitterOkText          = "Der Jitter (Latenzschwankung) zum Server liegt im normalen Bereich."
		DiagJitterWarnText        = "Der Jitter (Latenzschwankung) zum Server ist hoch, was während des Spiels zu Instabilität führen kann."
		DiagEndpointHighVsIcmpText = "Die Latenz zum FiveM-Endpoint ist deutlich höher als die Latenz deiner externen Verbindung."
		DiagCauseUnknownText      = "Wir konnten nicht feststellen, ob die Ursache bei deinem ISP, der Route oder dem Ziel liegt."
		DiagEndpointConsistentText = "Die Antwortzeit des FiveM-Endpoints stimmt mit der Latenz deiner Verbindung zu diesem Ziel überein."
		DiagEndpointFastNoBaselineText = "Der FiveM-Endpoint hat in normaler Zeit geantwortet."
		DiagEndpointModerateNoBaselineText = "Die Antwortzeit des Endpoints ist moderat, aber es gibt keine lokale Latenzreferenz zum Vergleich."
		DiagEndpointSlowNoBaselineText = "Die Antwortzeit des FiveM-Endpoints ist hoch."
		DiagEndpointUnreachableText = "Der Endpoint dieser Adresse hat nicht geantwortet - könnte der konfigurierte Port, ein offline Server oder eine Blockierung speziell dieses Ports sein."
		DiagEndpointUnreachableButNetworkOkText = "Dein Netzwerk kann diesen Host normal erreichen (Ping hat geantwortet), was darauf hindeutet, dass das Problem nicht allgemein bei deiner Verbindung liegt."
		DiagEndpointNotFXServerText = "Wir haben eine Antwort von dieser Adresse erhalten, aber sie scheint nicht von einem FiveM/RedM-Server zu stammen - prüfe, ob der Port korrekt ist."
		DiagEndpointRateLimitedText = "Der Server hat unsere Anfrage aus Sicherheitsgründen begrenzt - wir konnten den Endpoint bei diesem Versuch nicht bestätigen."
		RefreshButton             = "Erneut prüfen"
		CloseButton               = "Schließen"
		ThemeButtonLight          = "Heller Modus"
		ThemeButtonDark           = "Dunkler Modus"
		UpdateAvailableFormat     = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk                  = "Du hast die neueste Version."
		NewsHeader                = "Danke, dass du unsere App nutzt, schau vorbei:"
		FreeLabel                 = "Kostenloses Produkt bereitgestellt von NunoFoxs"
	}
	"fr" = @{
		Description               = "Vérifiez si votre connexion est assez bonne pour jouer à FiveM ou RedM."
		GameLabel                 = "Jeu"
		AddressLabel              = "Adresse du serveur (optionnel)"
		AddressPlaceholder        = "ex: 192.168.0.1:30120"
		CheckingLabel             = "Vérification..."
		InternetLabel             = "Internet"
		InternetOk                = "Active"
		InternetDown              = "Aucune connexion"
		DNSLabel                  = "DNS"
		DNSOk                     = "Fonctionne"
		DNSDown                   = "Ne fonctionne pas"
		LatencyNoAddressTitle     = "Adresse non configurée"
		LatencyNoAddressDesc      = "Renseignez l'adresse du serveur ci-dessus pour mesurer la latence."
		LatencyInvalidFormatTitle = "Format non pris en charge"
		LatencyInvalidFormatDesc  = "Ce format d'adresse ne peut pas être testé directement - utilisez le format IP:port."
		LatencyUnreachableTitle   = "Pas de réponse au ping"
		LatencyUnreachableDesc    = "Beaucoup de serveurs bloquent le ping par sécurité même en étant en ligne - cela ne signifie pas que le serveur est hors ligne. Si vous pouvez jouer normalement, vous pouvez l'ignorer."
		LatencyExcellentTitle     = "Latence excellente"
		LatencyGoodTitle          = "Bonne latence"
		LatencyOkTitle            = "Latence acceptable"
		LatencyHighTitle          = "Latence élevée"
		LatencyDescFormat         = "{0} ms de ping · {1} % de perte sur {2} tentatives."
		EndpointAccessibleTitle   = "Point d'accès FiveM joignable"
		EndpointConfirmedDescFormat = "FXServer confirmé : {0} ms"
		EndpointServerNameFormat  = "Nom du Serveur : {0}"
		EndpointNotAccessibleTitle = "Le point d'accès FiveM n'a pas répondu"
		EndpointUnreachableDesc   = "Impossible de joindre cette adresse:port sur le web - le serveur est peut-être hors ligne ou bloque ce type d'accès."
		EndpointNotFXServerDesc   = "Nous avons reçu une réponse de cette adresse, mais elle ne ressemble pas à un serveur FiveM/RedM."
		EndpointRateLimitedTitle  = "Limite de requêtes atteinte"
		EndpointRateLimitedDesc   = "Le serveur a limité notre requête par sécurité - réessayez dans un instant."
		DiagnosisHeader           = "Diagnostic"
		DiagInternetDownText      = "Nous n'avons pas pu confirmer la connectivité internet générale."
		DiagGatewayOkText         = "Votre réseau local présente une latence normale."
		DiagGatewayWarnText       = "Votre réseau local (jusqu'au routeur) présente une latence ou une perte hors norme - cela peut venir du Wi-Fi, du câble ou du routeur lui-même."
		DiagGatewayUnreachableText = "Le routeur local n'a pas répondu au test de latence (courant sur certains modèles, ne signifie pas forcément un problème)."
		DiagGatewayUnknownText    = "Nous n'avons pas pu déterminer la latence jusqu'au routeur local."
		DiagDnsOkText             = "Le DNS fonctionne normalement."
		DiagDnsSlowText           = "Le DNS fonctionne, mais la résolution de noms est lente."
		DiagDnsDownText           = "Le DNS n'a pas pu résoudre de noms pendant le test."
		DiagNoTargetText          = "Renseignez l'adresse du serveur ci-dessus pour inclure la latence, la perte de paquets et le point d'accès dans le diagnostic."
		DiagLossOkText            = "Aucune perte de paquets n'a été détectée lors de ce test."
		DiagLossWarnFormat        = "Une perte de paquets a été détectée sur le chemin vers le serveur ({0} %)."
		DiagLossUnknownText       = "Nous n'avons pas pu mesurer la perte de paquets par ping (le serveur bloque peut-être l'ICMP par sécurité)."
		DiagJitterOkText          = "La gigue (variation de latence) jusqu'au serveur est dans la normale."
		DiagJitterWarnText        = "La gigue (variation de latence) jusqu'au serveur est élevée, ce qui peut causer de l'instabilité pendant le jeu."
		DiagEndpointHighVsIcmpText = "La latence jusqu'au point d'accès FiveM est nettement supérieure à la latence de votre connexion externe."
		DiagCauseUnknownText      = "Nous n'avons pas pu déterminer si la cause vient de votre FAI, de la route ou de la destination."
		DiagEndpointConsistentText = "Le temps de réponse du point d'accès FiveM est cohérent avec la latence de votre connexion jusqu'à cette destination."
		DiagEndpointFastNoBaselineText = "Le point d'accès FiveM a répondu dans un délai considéré normal."
		DiagEndpointModerateNoBaselineText = "Le temps de réponse du point d'accès est modéré, mais il n'y a pas de référence de latence locale pour comparer."
		DiagEndpointSlowNoBaselineText = "Le temps de réponse du point d'accès FiveM est élevé."
		DiagEndpointUnreachableText = "Le point d'accès de cette adresse n'a pas répondu - cela peut être le port configuré, le serveur hors ligne, ou un blocage spécifique à ce port."
		DiagEndpointUnreachableButNetworkOkText = "Votre réseau peut atteindre cet hôte normalement (le ping a répondu), ce qui suggère que le problème n'est pas général à votre connexion."
		DiagEndpointNotFXServerText = "Nous avons reçu une réponse de cette adresse, mais elle ne semble pas provenir d'un serveur FiveM/RedM - vérifiez que le port est correct."
		DiagEndpointRateLimitedText = "Le serveur a limité notre requête par sécurité - nous n'avons pas pu confirmer le point d'accès lors de cette tentative."
		RefreshButton             = "Vérifier à nouveau"
		CloseButton               = "Fermer"
		ThemeButtonLight          = "Mode Clair"
		ThemeButtonDark           = "Mode Sombre"
		UpdateAvailableFormat     = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk                  = "Vous avez la dernière version."
		NewsHeader                = "Merci d'utiliser notre application, découvrez :"
		FreeLabel                 = "Produit gratuit proposé par NunoFoxs"
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

$TypedAddresses = @{
	"FiveM" = $Games["FiveM"].DefaultAddress
	"RedM"  = $Games["RedM"].DefaultAddress
}

$DefaultFont = Scale-Font 9

$IconPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS.ico"

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "NFXS - Connection"
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
$TitleLabel.Text = "NFXS | CONNECTION"
$TitleLabel.Font = Scale-Font 12 ([System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = Scale-Point 18 13
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.Text = "FiveM & RedM Connection Check v$AppVersion"
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
$DescriptionLabel.Size = Scale-SizeMinHeight 320 32 30
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
$GameCombo.Size = Scale-Size 320 26
$GameCombo.Font = $DefaultFont
$GameCombo.DropDownStyle = "DropDownList"
$GameCombo.Items.AddRange(@("FiveM","RedM"))
$GameCombo.SelectedItem = $Script:CurrentGame
$ContentPanel.Controls.Add($GameCombo)
$Y += (Scale-Val 34)

$AddressLabel = New-Object System.Windows.Forms.Label
$AddressLabel.Text = $Strings[$CurrentLang].AddressLabel
$AddressLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$AddressLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$AddressLabel.AutoSize = $true
$ContentPanel.Controls.Add($AddressLabel)
$Y += (Scale-Val 20)

$AddressBox = New-Object System.Windows.Forms.TextBox
$AddressBox.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$AddressBox.Size = Scale-Size 320 24
$AddressBox.Font = $DefaultFont
$AddressBox.Text = $TypedAddresses[$Script:CurrentGame]
$AddressBox.Add_TextChanged({ $TypedAddresses[$Script:CurrentGame] = $AddressBox.Text })
$ContentPanel.Controls.Add($AddressBox)
$Y += (Scale-Val 38)

$InternetNameLabel = New-Object System.Windows.Forms.Label
$InternetNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$InternetNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$InternetNameLabel.Size = Scale-Size 120 18
$ContentPanel.Controls.Add($InternetNameLabel)

$InternetValueLabel = New-Object System.Windows.Forms.Label
$InternetValueLabel.Font = $DefaultFont
$InternetValueLabel.Location = New-Object System.Drawing.Point((Scale-Val 140), $Y)
$InternetValueLabel.Size = Scale-Size 198 18
$InternetValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($InternetValueLabel)
$Y += (Scale-Val 22)

$DNSNameLabel = New-Object System.Windows.Forms.Label
$DNSNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$DNSNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$DNSNameLabel.Size = Scale-Size 120 18
$ContentPanel.Controls.Add($DNSNameLabel)

$DNSValueLabel = New-Object System.Windows.Forms.Label
$DNSValueLabel.Font = $DefaultFont
$DNSValueLabel.Location = New-Object System.Drawing.Point((Scale-Val 140), $Y)
$DNSValueLabel.Size = Scale-Size 198 18
$DNSValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($DNSValueLabel)
$Y += (Scale-Val 28)

$EndpointTitleLabel = New-Object System.Windows.Forms.Label
$EndpointTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$EndpointTitleLabel.Size = Scale-Size 320 16
$EndpointTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($EndpointTitleLabel)
$Y += (Scale-Val 16)

$EndpointDescLabel = New-Object System.Windows.Forms.Label
$EndpointDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$EndpointDescLabel.AutoSize = $true
$EndpointDescLabel.MaximumSize = New-Object System.Drawing.Size((Scale-Val 320), 0)
$EndpointDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($EndpointDescLabel)

$IcmpTitleLabel = New-Object System.Windows.Forms.Label
$IcmpTitleLabel.Size = Scale-Size 320 16
$IcmpTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($IcmpTitleLabel)

$IcmpDescLabel = New-Object System.Windows.Forms.Label
$IcmpDescLabel.AutoSize = $true
$IcmpDescLabel.MaximumSize = New-Object System.Drawing.Size((Scale-Val 320), 0)
$IcmpDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($IcmpDescLabel)

$DiagnosisHeaderLabel = New-Object System.Windows.Forms.Label
$DiagnosisHeaderLabel.Size = Scale-Size 320 16
$DiagnosisHeaderLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($DiagnosisHeaderLabel)

$DiagnosisPanel = New-Object System.Windows.Forms.Panel
$DiagnosisPanel.Size = Scale-Size 320 16
$DiagnosisPanel.AutoScroll = $false
$ContentPanel.Controls.Add($DiagnosisPanel)

$RefreshButton = New-Object System.Windows.Forms.Button
$RefreshButton.Font = $DefaultFont
$RefreshButton.Size = Scale-Size 152 34
$RefreshButton.FlatStyle = "Flat"
$RefreshButton.FlatAppearance.BorderSize = 0
$RefreshButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$ContentPanel.Controls.Add($RefreshButton)

$CloseButton = New-Object System.Windows.Forms.Button
$CloseButton.Font = $DefaultFont
$CloseButton.Size = Scale-Size 152 34
$CloseButton.FlatStyle = "Flat"
$CloseButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$CloseButton.Add_Click({ $Form.Close() })
$ContentPanel.Controls.Add($CloseButton)

$UpdateLabel = New-Object System.Windows.Forms.Label
$UpdateLabel.Size = Scale-Size 320 18
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
$ContentPanel.Controls.Add($UpdateLabel)

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
$FreeLabel.Font = Scale-Font 7.5
$FreeLabel.TextAlign = "MiddleCenter"
$FreeLabel.Location = Scale-Point 18 38
$FreeLabel.Size = Scale-Size 344 16
$DiscordPanel.Controls.Add($FreeLabel)

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

function Get-GameAccentColor($GameName, $ThemeName) {
	$T = $Themes[$ThemeName]
	if ($GameName -eq "RedM") {
		if ($ThemeName -eq "Dark") { return $T.RedMLight }
		return $T.RedMPrimary
	}
	return $T.Accent
}

function Get-DiagnosisFindings($Diag) {
	$S = $Strings[$CurrentLang]
	$Findings = @()

	if (-not $Diag.Internet.Active) {
		$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagInternetDownText }
	}

	if (-not $Diag.GatewayPing) {
		$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagGatewayUnknownText }
	} elseif (-not $Diag.GatewayPing.Reachable) {
		$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagGatewayUnreachableText }
	} elseif ($Diag.GatewayPing.AvgMs -le 15 -and $Diag.GatewayPing.LossPercent -eq 0) {
		$Findings += [PSCustomObject]@{ Level = "Ok"; Text = $S.DiagGatewayOkText }
	} else {
		$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagGatewayWarnText }
	}

	if ($Diag.DNS.Working) {
		if ($Diag.DNS.ResolutionMs -and $Diag.DNS.ResolutionMs -gt 200) {
			$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagDnsSlowText }
		} else {
			$Findings += [PSCustomObject]@{ Level = "Ok"; Text = $S.DiagDnsOkText }
		}
	} else {
		$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagDnsDownText }
	}

	if (-not $Diag.Target) {
		$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagNoTargetText }
		return $Findings
	}

	$Icmp = $Diag.IcmpPing
	if ($Icmp -and $Icmp.Reachable) {
		if ($Icmp.LossPercent -eq 0) {
			$Findings += [PSCustomObject]@{ Level = "Ok"; Text = $S.DiagLossOkText }
		} else {
			$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagLossWarnFormat -f $Icmp.LossPercent }
		}
		if ($null -ne $Icmp.JitterMs) {
			if ($Icmp.JitterMs -le 20) {
				$Findings += [PSCustomObject]@{ Level = "Ok"; Text = $S.DiagJitterOkText }
			} else {
				$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagJitterWarnText }
			}
		}
	} else {
		$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagLossUnknownText }
	}

	$FiveM = $Diag.FiveM
	if ($FiveM -and $FiveM.FXServerConfirmed) {
		if ($Icmp -and $Icmp.Reachable -and $Icmp.AvgMs) {
			$Diff = $FiveM.ResponseMs - $Icmp.AvgMs
			if ($FiveM.ResponseMs -gt ($Icmp.AvgMs * 2) -and $Diff -gt 80) {
				$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagEndpointHighVsIcmpText }
				$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagCauseUnknownText }
			} else {
				$Findings += [PSCustomObject]@{ Level = "Ok"; Text = $S.DiagEndpointConsistentText }
			}
		} else {
			if ($FiveM.ResponseMs -le 300) {
				$Findings += [PSCustomObject]@{ Level = "Ok"; Text = $S.DiagEndpointFastNoBaselineText }
			} elseif ($FiveM.ResponseMs -le 700) {
				$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagEndpointModerateNoBaselineText }
			} else {
				$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagEndpointSlowNoBaselineText }
				$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagCauseUnknownText }
			}
		}
	} elseif ($FiveM) {
		if ($FiveM.HttpStatus -eq 429) {
			$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagEndpointRateLimitedText }
		} elseif ($FiveM.HttpStatus) {
			$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagEndpointNotFXServerText }
		} else {
			$Findings += [PSCustomObject]@{ Level = "Warning"; Text = $S.DiagEndpointUnreachableText }
			if ($Icmp -and $Icmp.Reachable) {
				$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagEndpointUnreachableButNetworkOkText }
			} else {
				$Findings += [PSCustomObject]@{ Level = "Info"; Text = $S.DiagCauseUnknownText }
			}
		}
	}

	return $Findings
}

function Set-DiagnosisFindings($Findings) {
	$T = $Themes[$CurrentTheme]
	$DiagnosisPanel.Controls.Clear()
	$Y = 0
	foreach ($Finding in $Findings) {
		$Lbl = New-Object System.Windows.Forms.Label
		$Lbl.AutoSize = $true
		$Lbl.MaximumSize = New-Object System.Drawing.Size((Scale-Val 320), 0)
		$Lbl.Font = Scale-Font 8
		$Lbl.Text = $Finding.Text
		$Lbl.ForeColor = switch ($Finding.Level) {
			"Ok"      { $T.Success }
			"Warning" { $T.Warning }
			default   { $T.TextSoft }
		}
		$Lbl.Location = New-Object System.Drawing.Point(0, $Y)
		$DiagnosisPanel.Controls.Add($Lbl)
		$Y += $Lbl.Height + (Scale-Val 6)
	}
	$DiagnosisPanel.Height = [Math]::Max((Scale-Val 16), $Y)
}

function Update-Layout {
	$IcmpTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), ($EndpointDescLabel.Bottom + (Scale-Val 10)))
	$IcmpDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), ($IcmpTitleLabel.Bottom + (Scale-Val 4)))
	$DiagnosisHeaderLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), ($IcmpDescLabel.Bottom + (Scale-Val 10)))
	$DiagnosisPanel.Location = New-Object System.Drawing.Point((Scale-Val 18), ($DiagnosisHeaderLabel.Bottom + (Scale-Val 4)))

	$Y = $DiagnosisPanel.Bottom + (Scale-Val 10)
	$RefreshButton.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$CloseButton.Location = New-Object System.Drawing.Point((Scale-Val 186), $Y)
	$Y += (Scale-Val 34) + (Scale-Val 16)
	$UpdateLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$Y += (Scale-Val 18) + (Scale-Val 10)

	$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, $Y)
}

function Run-Checks {
	$S = $Strings[$CurrentLang]
	$T = $Themes[$CurrentTheme]
	$GameName = $Script:CurrentGame

	$InternetOk = Test-InternetActive
	$InternetValueLabel.Text = if ($InternetOk) { $S.InternetOk } else { $S.InternetDown }
	$InternetValueLabel.ForeColor = if ($InternetOk) { $T.Success } else { $T.Error }

	$DNSInfo = Get-DNSInfo
	$DNSValueLabel.Text = if ($DNSInfo.Working) { $S.DNSOk } else { $S.DNSDown }
	$DNSValueLabel.ForeColor = if ($DNSInfo.Working) { $T.Success } else { $T.Error }

	$LocalNet = Get-LocalNetworkInfo
	$PublicIP = Get-PublicIP
	$GatewayPing = if ($LocalNet -and $LocalNet.Gateway) { Test-PingStats $LocalNet.Gateway 2 } else { $null }

	$Address = $AddressBox.Text.Trim()
	$Target = Get-HostAndPort $Address
	$IcmpStats = $null
	$FiveMResult = $null

	if (-not $Address) {
		$EndpointTitleLabel.Text = $S.LatencyNoAddressTitle
		$EndpointTitleLabel.ForeColor = $T.TextSoft
		$EndpointDescLabel.Text = $S.LatencyNoAddressDesc
		$IcmpTitleLabel.Text = ""
		$IcmpDescLabel.Text = ""
	} elseif (-not $Target) {
		$EndpointTitleLabel.Text = $S.LatencyInvalidFormatTitle
		$EndpointTitleLabel.ForeColor = $T.TextSoft
		$EndpointDescLabel.Text = $S.LatencyInvalidFormatDesc
		$IcmpTitleLabel.Text = ""
		$IcmpDescLabel.Text = ""
	} else {
		$FiveMResult = Test-FiveMEndpoint $Target.HostName $Target.Port
		if ($FiveMResult.FXServerConfirmed) {
			$EndpointTitleLabel.Text = $S.EndpointAccessibleTitle
			$EndpointTitleLabel.ForeColor = $T.Success
			$DescLines = @()
			if ($FiveMResult.ServerName) {
				$DescLines += ($S.EndpointServerNameFormat -f $FiveMResult.ServerName)
			}
			$DescLines += ($S.EndpointConfirmedDescFormat -f $FiveMResult.ResponseMs)
			$EndpointDescLabel.Text = $DescLines -join "`n"
		} elseif ($FiveMResult.HttpStatus -eq 429) {
			$EndpointTitleLabel.Text = $S.EndpointRateLimitedTitle
			$EndpointTitleLabel.ForeColor = $T.Warning
			$EndpointDescLabel.Text = $S.EndpointRateLimitedDesc
		} elseif ($FiveMResult.HttpStatus) {
			$EndpointTitleLabel.Text = $S.EndpointNotAccessibleTitle
			$EndpointTitleLabel.ForeColor = $T.Error
			$EndpointDescLabel.Text = $S.EndpointNotFXServerDesc
		} else {
			$EndpointTitleLabel.Text = $S.EndpointNotAccessibleTitle
			$EndpointTitleLabel.ForeColor = $T.Error
			$EndpointDescLabel.Text = $S.EndpointUnreachableDesc
		}

		$IcmpStats = Test-PingStats $Target.HostName
		if (-not $IcmpStats.Reachable) {
			$IcmpTitleLabel.Text = $S.LatencyUnreachableTitle
			$IcmpTitleLabel.ForeColor = $T.TextSoft
			$IcmpDescLabel.Text = $S.LatencyUnreachableDesc
		} else {
			$LatLevel = Get-LatencyLevel $IcmpStats.AvgMs
			$IcmpTitleLabel.Text = $LatLevel.Title
			$IcmpTitleLabel.ForeColor = $T[$LatLevel.ColorKey]
			$IcmpDescLabel.Text = $S.LatencyDescFormat -f $IcmpStats.AvgMs, $IcmpStats.LossPercent, $IcmpStats.Sent
		}
	}
	$EndpointDescLabel.ForeColor = $T.TextSoft
	$IcmpDescLabel.ForeColor = $T.TextSoft

	$Script:Diagnostic = [PSCustomObject]@{
		Timestamp    = Get-Date
		Game         = $GameName
		Address      = $Address
		Target       = $Target
		Internet     = [PSCustomObject]@{ Active = $InternetOk }
		DNS          = $DNSInfo
		LocalNetwork = $LocalNet
		PublicIP     = $PublicIP
		GatewayPing  = $GatewayPing
		IcmpPing     = $IcmpStats
		FiveM        = $FiveMResult
	}

	$Findings = Get-DiagnosisFindings $Script:Diagnostic
	Set-DiagnosisFindings $Findings
	Update-Layout
}

function Set-Theme($Name) {
	$T = $Themes[$Name]
	$Script:CurrentTheme = $Name
	$GameAccent = Get-SharedAccentColor $Name
	$Script:GameAccent = $GameAccent

	$Form.BackColor = $T.FormBg
	$HeaderPanel.BackColor = $T.HeaderBg
	$ContentPanel.BackColor = $T.FormBg
	$BannerPanel.BackColor = $T.FormBg
	$DiscordPanel.BackColor = $T.FormBg
	$TitleLabel.ForeColor = $T.HeaderTitle
	$SubtitleLabel.ForeColor = $T.HeaderSub
	$UpdateLabel.ForeColor = if ($UpdateAvailable) { $T.Error } else { $T.Success }
	$DescriptionLabel.ForeColor = $T.TextSoft
	$GameLabel.ForeColor = $T.Text
	$GameCombo.BackColor = $T.FieldBg
	$GameCombo.ForeColor = $T.FieldFg
	$AddressLabel.ForeColor = $T.Text
	$AddressBox.BackColor = $T.FieldBg
	$AddressBox.ForeColor = $GameAccent
	$InternetNameLabel.ForeColor = $T.Text
	$DNSNameLabel.ForeColor = $T.Text
	$DiagnosisHeaderLabel.ForeColor = $T.Text
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
	$AddressLabel.Text = $S.AddressLabel
	Set-CueBanner $AddressBox $S.AddressPlaceholder
	$InternetNameLabel.Text = $S.InternetLabel
	$DNSNameLabel.Text = $S.DNSLabel
	$DiagnosisHeaderLabel.Text = $S.DiagnosisHeader
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

}

$GameCombo.Add_SelectedIndexChanged({
	$Script:CurrentGame = $GameCombo.SelectedItem
	Save-Game $GameCombo.SelectedItem
	$AddressBox.Text = $TypedAddresses[$Script:CurrentGame]
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

[System.Windows.Forms.Application]::EnableVisualStyles()

$null = $Form.Handle
Set-Theme $CurrentTheme
Apply-Language $CurrentLang
Set-AutoEllipsisRecursive $HeaderPanel
Set-AutoEllipsisRecursive $BannerPanel
Set-AutoEllipsisRecursive $DiscordPanel

$PlaceholderText = $Strings[$CurrentLang].CheckingLabel
$InternetValueLabel.Text = $PlaceholderText
$DNSValueLabel.Text = $PlaceholderText
$EndpointTitleLabel.Text = $PlaceholderText
$IcmpTitleLabel.Text = $PlaceholderText
foreach ($Lbl in @($InternetValueLabel,$DNSValueLabel,$EndpointTitleLabel,$IcmpTitleLabel)) {
	$Lbl.ForeColor = $Themes[$CurrentTheme].TextSoft
}

$Form.Add_Shown({
	Run-Checks
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	$ContentPanel.BeginInvoke([Action]{
		$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	}) | Out-Null
})
$Form.ShowDialog() | Out-Null
