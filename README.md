# Agente de leitura de digital

Programa que roda **na maquina da recepcao**, junto com o navegador, e serve
de ponte entre a tela do UltraAcesso e o leitor de digital USB.

O navegador nao consegue acender um leitor USB sozinho. Por isso a tela de
cadastro de funcionario chama `http://localhost:5009/api/capture.json` e
espera que alguem na maquina do operador atenda. Esse alguem e este programa.

> Ate aqui esse programa **nao existia**. A chamada dava
> `ERR_CONNECTION_REFUSED`, o JavaScript estourava logo depois e o botao
> "Ler" nao fazia nada — sem mensagem na tela, sem nada no log do servidor.

## Onde instalar

Na maquina onde o **leitor esta espetado** — a da recepcao —, nao no servidor.
O servidor nunca fala com o leitor; ele so recebe a digital pronta, junto com
o formulario.

## Requisitos

- Windows
- Leitor **Suprema** (testado com BioMini Plus 2) com o **driver instalado**
- .NET Framework 4.8 (ja vem no Windows 10 e 11)

Sem o driver, o leitor aparece como "dispositivo desconhecido" no Gerenciador
de Dispositivos e o agente responde "Nenhum leitor encontrado".

## Como instalar

Descompacte o zip inteiro e, dentro da pasta, abra o PowerShell e rode:

```powershell
.\instalar.ps1
```

Ele copia tudo para `C:\UltraAcesso\agente-leitor`, registra o agente para
**iniciar junto com o Windows**, sobe na hora e confere se o leitor foi
reconhecido — dizendo na tela o que deu certo e o que faltou.

Para remover: `.\desinstalar.ps1`.

### Por que inicia com o usuario, e nao como servico

O instalador do UltraAcesso registra o servidor como SYSTEM e `-AtStartup`.
Aqui e `-AtLogOn`, com o usuario interativo, de proposito: o agente conversa
com um leitor USB e atende o navegador daquela pessoa em `localhost`. Como
SYSTEM, na sessao 0, nao alcanca nem um nem outro.

### Rodar na mao, sem instalar

```
AgenteLeitor.exe
```

Deixe a janela aberta enquanto estiver cadastrando digitais. Para usar outra
porta: `AgenteLeitor.exe 5010`.

**Todos os arquivos precisam ficar na mesma pasta do `.exe`** — o SDK carrega
`UFScanner.dll` e `UFLicense.dat` pelo nome, a partir do diretorio do
executavel.

## Conferir se esta funcionando

Abra no navegador da propria maquina:

```
http://localhost:5009/api/status.json
```

- `{"status":"OK","leitores":1}` — agente no ar e leitor reconhecido
- `{"status":"OK","leitores":0}` — agente no ar, mas sem leitor (driver ou cabo)
- nao abre — o agente nao esta rodando

Esse endereco nao pede o dedo, entao serve para testar a instalacao sem
ninguem por perto.

## O que ele responde

`GET /api/capture.json` acende o leitor, espera o dedo (ate 15 segundos) e
devolve:

```json
{"status":"OK","template":"MXvGJx...","qualidade":72}
```

Em qualquer erro, devolve so o `status` com uma frase em portugues — e a
propria tela do UltraAcesso mostra essa frase para o operador, porque o
JavaScript ja joga `status` na tela.

## Detalhes que custaram a ser descobertos

**O template sai com tamanho variavel.** O `Extract()` devolve 342 ou 332
bytes conforme a quantidade de minucias, mas o destino espera o **slot
inteiro de 384 bytes**, com zeros no fim. Cortar para o tamanho real faz o
equipamento recusar a gravacao.

**Tem que ser x86.** As DLLs nativas sao de 32 bits; compilar em x64 ou
AnyCPU quebra no carregamento com `BadImageFormatException`.

**O envelope `1{`.** O UltraAcesso descarta tudo ate a primeira chave e usa o
que vem depois (`fingerprint.py`, `to_henry_format`). O agente ja entrega
nesse formato.

**O cabecalho de CORS.** A tela vem do servidor e o agente responde de
`localhost`: para o navegador sao origens diferentes. Sem
`Access-Control-Allow-Origin`, a resposta e bloqueada e volta o mesmo "nao
acontece nada".

## Como gerar o executavel

Nenhuma maquina Linux compila isso — .NET nao faz cross-compile para
`net48` com wrapper nativo. Use o GitHub Actions: **Actions -> Build Agente
Leitor (.exe) -> Run workflow**. O `.exe` sai como artefato para download.

O workflow so passa com o SDK em `libs/` (ver [libs/README.md](libs/README.md)).

## As bibliotecas nao estao aqui

O SDK da **Suprema** (hoje **Xperix**) e binario e licenca de terceiro, entao
`libs/` esta vazia neste repositorio. **O projeto nao compila sem ela** —
veja [libs/README.md](libs/README.md) para o que baixar e onde colocar.

Para mexer no codigo sem leitor e sem SDK, o `simulador.py` sobe na mesma
porta e responde no mesmo formato.

## Limite conhecido

Este agente fala com leitor **Suprema**. As catracas **Topdata** usam modulos
biometricos **Nitgen** (linha FIM, sensores OPP) — template de uma marca nao e
aceito pela outra. Para mandar digital a uma Topdata, o leitor da recepcao
precisa ser Nitgen (o "Hamster LFD" citado na documentacao da propria
Topdata), e sera preciso um agente equivalente sobre o SDK da Nitgen.
