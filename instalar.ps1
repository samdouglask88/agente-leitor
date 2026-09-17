# Instalador do agente de leitura de digital.
#
# Diferente do instalador do UltraAcesso, que registra o servico como SYSTEM
# e -AtStartup: o agente PRECISA rodar na sessao de quem esta usando o
# computador. Ele conversa com um leitor USB e atende o navegador daquela
# pessoa em localhost - como SYSTEM, na sessao 0, nao enxerga nem um nem
# outro. Por isso aqui e -AtLogOn, com o usuario interativo.
#
# Uso (PowerShell na maquina da recepcao):
#   .\instalar.ps1

$ErrorActionPreference = "Stop"

$INSTALL_DIR = "C:\UltraAcesso\agente-leitor"
$TASK_NAME   = "UltraAcesso-AgenteLeitor"
$EXE         = "$INSTALL_DIR\AgenteLeitor.exe"
$PORTA       = 5009

function Write-Ok    ($m) { Write-Host "  [ok] $m"     -ForegroundColor Green }
function Write-Aviso ($m) { Write-Host "  [aviso] $m"  -ForegroundColor Yellow }
function Write-Erro  ($m) { Write-Host "  [erro] $m"   -ForegroundColor Red }

Write-Host ""
Write-Host "Instalador do Agente de Leitura de Digital - UltraAcesso"
Write-Host "========================================================"
Write-Host ""

# --- 1. Conferir que os arquivos estao todos aqui -----------------------
# O SDK carrega UFScanner.dll e UFLicense.dat pelo nome, a partir da pasta do
# executavel. Instalar so o .exe produz um erro obscuro na inicializacao.
$origem = $PSScriptRoot
$necessarios = @("AgenteLeitor.exe", "UFScanner.dll", "UFLicense.dat", "Suprema.UFScanner.dll")
$faltando = @()
foreach ($arquivo in $necessarios) {
    if (-not (Test-Path (Join-Path $origem $arquivo))) { $faltando += $arquivo }
}
if ($faltando.Count -gt 0) {
    Write-Erro "Faltam arquivos nesta pasta: $($faltando -join ', ')"
    Write-Host "  Descompacte o zip inteiro e rode o instalador de dentro dele."
    exit 1
}
Write-Ok "Arquivos conferidos"

# --- 2. .NET Framework 4.8 ----------------------------------------------
$release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Release
if ($null -eq $release -or $release -lt 528040) {
    Write-Aviso ".NET Framework 4.8 nao detectado. O agente pode nao iniciar."
    Write-Host "  Baixe em: https://dotnet.microsoft.com/download/dotnet-framework/net48"
} else {
    Write-Ok ".NET Framework 4.8 presente"
}

# --- 3. Parar o que ja estiver rodando ----------------------------------
Get-Process -Name "AgenteLeitor" -ErrorAction SilentlyContinue | ForEach-Object {
    # Windows nao sobrescreve arquivo em uso: sem isto a copia abaixo falha
    # numa reinstalacao.
    $_.Kill()
    Start-Sleep -Seconds 1
    Write-Ok "Agente anterior encerrado"
}

# --- 4. Copiar -----------------------------------------------------------
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Copy-Item "$origem\*" $INSTALL_DIR -Recurse -Force -Exclude "instalar.ps1", "desinstalar.ps1"
Write-Ok "Instalado em $INSTALL_DIR"

# --- 5. Iniciar junto com a sessao do usuario ---------------------------
$existente = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
if ($existente) {
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
    Write-Ok "Tarefa anterior removida"
}

$action  = New-ScheduledTaskAction -Execute $EXE -WorkingDirectory $INSTALL_DIR
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
# Interactive de proposito: e a unica forma de alcancar o leitor USB e o
# navegador da pessoa. Nada de SYSTEM aqui.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

Register-ScheduledTask `
    -TaskName $TASK_NAME `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Ponte entre o navegador e o leitor de digital do UltraAcesso" | Out-Null
Write-Ok "Configurado para iniciar junto com o Windows"

# --- 6. Subir agora ------------------------------------------------------
Start-ScheduledTask -TaskName $TASK_NAME
Start-Sleep -Seconds 3

# --- 7. Conferir de verdade ---------------------------------------------
Write-Host ""
Write-Host "Conferindo..."
try {
    $r = Invoke-RestMethod -Uri "http://localhost:$PORTA/api/status.json" -TimeoutSec 5
    Write-Ok "Agente respondendo em http://localhost:$PORTA"
    if ($r.leitores -ge 1) {
        Write-Ok "Leitor de digital reconhecido"
        Write-Host ""
        Write-Host "  Pronto. Abra o UltraAcesso neste computador e use o botao Ler." -ForegroundColor Green
    } else {
        Write-Aviso "Agente no ar, mas NENHUM leitor encontrado."
        Write-Host "  Espete o leitor e confira o driver no Gerenciador de Dispositivos."
        Write-Host "  Se aparecer 'dispositivo desconhecido', falta o driver do fabricante."
    }
} catch {
    Write-Erro "O agente nao respondeu na porta $PORTA."
    Write-Host "  Veja a tarefa '$TASK_NAME' no Agendador de Tarefas,"
    Write-Host "  ou rode $EXE na mao para ver a mensagem de erro."
    exit 1
}

Write-Host ""
Write-Host "Para desinstalar: .\desinstalar.ps1"
Write-Host ""
