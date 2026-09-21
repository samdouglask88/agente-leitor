# Agente de leitura de digital - versao PowerShell, sem compilar nada.
#
# Existe porque o caminho do executavel depende de compilar em Windows (as
# bibliotecas da Suprema sao nativas de 32 bits) e nenhuma maquina da equipe
# faz isso: cada tentativa vira um ciclo de build no CI, no escuro. O
# PowerShell ja vem em todo Windows e carrega a mesma biblioteca direto.
#
# Faz exatamente o que o AgenteLeitor.exe faz, e responde igual.
#
# TEM QUE RODAR EM 32 BITS. As DLLs nativas sao x86; no PowerShell de 64 bits
# o carregamento falha com BadImageFormatException. Use o agente.bat ao lado,
# que ja chama o PowerShell certo.

param(
    [int]$Porta = 5009
)

$ErrorActionPreference = "Stop"

$SLOT_SUPREMA_2001 = 384
$TIPO_TEMPLATE_2001 = 2001

if ([IntPtr]::Size -ne 4) {
    Write-Host "ERRO: este script precisa rodar no PowerShell de 32 bits." -ForegroundColor Red
    Write-Host "Use o agente.bat que esta nesta pasta, ou rode:"
    Write-Host "  $env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File agente.ps1"
    exit 1
}

Write-Host "Agente de leitura de digital (PowerShell)"
Write-Host "Carregando a biblioteca da Suprema..."

# As DLLs ficam em libs\ no repositorio, mas ao lado do .exe quando o projeto
# e compilado. Procurar nos dois lugares evita que rodar direto do repositorio
# (que e como se testa antes de existir executavel) morra sem motivo.
$pastasCandidatas = @(
    (Join-Path $PSScriptRoot "libs"),
    $PSScriptRoot
)

$pastaDll = $null
foreach ($pasta in $pastasCandidatas) {
    if (Test-Path (Join-Path $pasta "Suprema.UFScanner.dll")) {
        $pastaDll = $pasta
        break
    }
}

if (-not $pastaDll) {
    Write-Host "ERRO: nao achei Suprema.UFScanner.dll." -ForegroundColor Red
    Write-Host "Procurei em:"
    foreach ($pasta in $pastasCandidatas) { Write-Host "  $pasta" }
    exit 1
}

# O SDK carrega UFScanner.dll (a nativa) pelo NOME, a partir do diretorio de
# trabalho - nao do diretorio do script. Sem este Set-Location, a wrapper
# carrega e a nativa nao, com erro bem menos obvio.
Set-Location $pastaDll
Write-Host "Bibliotecas em: $pastaDll"
Add-Type -Path (Join-Path $pastaDll "Suprema.UFScanner.dll")

# PowerShell trata "New-Object Tipo($null)" como CHAMADA SEM ARGUMENTO, entao
# ele procura um construtor vazio que nao existe - o C# equivalente
# (new UFScannerManager(null)) funciona porque o tipo do parametro e conhecido
# na compilacao. Aqui e preciso forcar o nulo a contar como argumento, e as
# formas de fazer isso variam com a versao do PowerShell. Tenta todas, e se
# nenhuma servir mostra os construtores reais em vez de so reclamar.
$manager = $null
$tentativas = @()

try { $manager = [Suprema.UFScannerManager]::new($null) }
catch { $tentativas += "::new(`$null) -> $($_.Exception.Message)" }

if ($null -eq $manager) {
    try { $manager = New-Object Suprema.UFScannerManager -ArgumentList @($null) }
    catch { $tentativas += "-ArgumentList @(`$null) -> $($_.Exception.Message)" }
}

if ($null -eq $manager) {
    try { $manager = New-Object Suprema.UFScannerManager }
    catch { $tentativas += "sem argumento -> $($_.Exception.Message)" }
}

if ($null -eq $manager) {
    Write-Host "ERRO: nao consegui criar o UFScannerManager." -ForegroundColor Red
    foreach ($t in $tentativas) { Write-Host "  $t" }
    Write-Host ""
    Write-Host "Construtores que este SDK realmente tem:"
    foreach ($c in [Suprema.UFScannerManager].GetConstructors()) {
        $parametros = ($c.GetParameters() | ForEach-Object { "$($_.ParameterType.FullName) $($_.Name)" }) -join ", "
        Write-Host "  UFScannerManager($parametros)"
    }
    exit 1
}

$status = $manager.Init()
if ($status -ne [Suprema.UFS_STATUS]::OK) {
    Write-Host "ERRO: falha ao inicializar o SDK: $status" -ForegroundColor Red
    Write-Host "Confira se UFScanner.dll e UFLicense.dat estao nesta pasta."
    exit 1
}

if ($manager.Scanners.Count -eq 0) {
    Write-Host "AVISO: nenhum leitor encontrado agora." -ForegroundColor Yellow
} else {
    Write-Host "Leitor encontrado: $($manager.Scanners[0].ID)" -ForegroundColor Green
}

function Get-Digital {
    if ($manager.Scanners.Count -eq 0) {
        # O leitor pode ter sido espetado depois que o agente subiu.
        try { $manager.UpdateScannerList() } catch { }
    }
    if ($manager.Scanners.Count -eq 0) {
        return @{ status = "Nenhum leitor encontrado. Espete o leitor e confira o driver." }
    }

    $scanner = $manager.Scanners[0]
    $scanner.nTemplateType = $TIPO_TEMPLATE_2001
    $scanner.DetectCore = $false
    # Sem prazo, a espera pelo dedo nunca termina e a requisicao fica pendurada.
    try { $scanner.Timeout = 15000 } catch { }

    Write-Host "Aguardando dedo no leitor..."
    $st = $scanner.CaptureSingleImage()
    if ($st -ne [Suprema.UFS_STATUS]::OK) {
        if ("$st" -eq "TIMEOUT") {
            return @{ status = "Tempo esgotado. Ninguem encostou o dedo no leitor." }
        }
        return @{ status = "Falha ao capturar: $st" }
    }

    $buffer = New-Object byte[] $SLOT_SUPREMA_2001
    $tamanho = 0
    $qualidade = 0
    $st = $scanner.Extract($buffer, [ref]$tamanho, [ref]$qualidade)
    if ($st -ne [Suprema.UFS_STATUS]::OK) {
        return @{ status = "Falha ao extrair a digital: $st" }
    }

    Write-Host "Capturado: qualidade $qualidade, template real $tamanho bytes." -ForegroundColor Green

    # O buffer inteiro de 384 bytes, com os zeros de padding no fim - nada de
    # cortar para o tamanho real, senao o equipamento recusa a gravacao.
    #
    # O "1{" na frente e o envelope que o sistema consumidor espera: em
    # fingerprint.py, to_henry_format descarta tudo ate a primeira chave.
    $envelope = [System.Text.Encoding]::ASCII.GetBytes("1{")
    $corpo = New-Object byte[] ($envelope.Length + $SLOT_SUPREMA_2001)
    [Array]::Copy($envelope, 0, $corpo, 0, $envelope.Length)
    [Array]::Copy($buffer, 0, $corpo, $envelope.Length, $SLOT_SUPREMA_2001)

    return @{
        status    = "OK"
        template  = [Convert]::ToBase64String($corpo)
        qualidade = $qualidade
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Porta/")
try {
    $listener.Start()
} catch {
    Write-Host "ERRO: nao consegui escutar na porta $Porta. $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "No ar em http://localhost:$Porta/" -ForegroundColor Green
Write-Host "Deixe esta janela aberta enquanto usar o cadastro de digitais."
Write-Host "Ctrl+C para encerrar."
Write-Host ""

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $caminho = $ctx.Request.Url.AbsolutePath

    $resposta = switch ($caminho) {
        "/api/capture.json" {
            if ($ctx.Request.HttpMethod -eq "OPTIONS") { @{} } else { Get-Digital }
        }
        "/api/status.json" {
            @{ status = "OK"; leitores = $manager.Scanners.Count }
        }
        default {
            $ctx.Response.StatusCode = 404
            @{ status = "Endereco desconhecido: $caminho" }
        }
    }

    $json = $resposta | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    # A tela vem do servidor e o agente responde de localhost: para o
    # navegador sao origens diferentes. Sem este cabecalho ele bloqueia a
    # resposta e o operador ve o mesmo "nao acontece nada".
    $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $ctx.Response.ContentType = "application/json; charset=utf-8"
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}
