# Remove o agente de leitura de digital desta maquina.

$ErrorActionPreference = "Continue"

$INSTALL_DIR = "C:\UltraAcesso\agente-leitor"
$TASK_NAME   = "UltraAcesso-AgenteLeitor"

Write-Host ""
Write-Host "Desinstalando o Agente de Leitura de Digital"
Write-Host "============================================"

$tarefa = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
if ($tarefa) {
    Stop-ScheduledTask  -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
    Write-Host "  [ok] Tarefa agendada removida" -ForegroundColor Green
} else {
    Write-Host "  [ok] Nao havia tarefa agendada" -ForegroundColor Green
}

# O Windows nao apaga arquivo em uso: encerrar antes evita deixar a pasta
# pela metade.
Get-Process -Name "AgenteLeitor" -ErrorAction SilentlyContinue | ForEach-Object {
    $_.Kill()
    Start-Sleep -Seconds 1
    Write-Host "  [ok] Agente encerrado" -ForegroundColor Green
}

if (Test-Path $INSTALL_DIR) {
    Remove-Item $INSTALL_DIR -Recurse -Force
    Write-Host "  [ok] $INSTALL_DIR removido" -ForegroundColor Green
}

Write-Host ""
Write-Host "Pronto. O driver do leitor continua instalado (removivel pelo"
Write-Host "Gerenciador de Dispositivos, se quiser)."
Write-Host ""
