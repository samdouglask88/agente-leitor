@echo off
REM Sobe o agente no PowerShell de 32 bits. As DLLs nativas da Suprema sao
REM x86: no PowerShell de 64 bits o carregamento falha com
REM BadImageFormatException, e a mensagem nao ajuda ninguem.
title Agente de Leitura de Digital
"%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0agente.ps1" %*
pause
