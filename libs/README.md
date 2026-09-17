# O que falta nesta pasta

Tres arquivos do SDK da Suprema (hoje **Xperix**), que **nao estao
versionados** neste repositorio porque sao binario e licenca de terceiro:

| Arquivo | O que e |
|---|---|
| `Suprema.UFScanner.dll` | wrapper .NET, ~28 KB — e o que o `.csproj` referencia |
| `UFScanner.dll` | biblioteca nativa de 32 bits, ~5,6 MB |
| `UFLicense.dat` | arquivo de licenca, 256 bytes |

Sao do **UniFinger Engine SDK 3.4** (o wrapper e de 2012, .NET 1.1). Para
obter: peca o SDK ao fabricante, com licenca em nome da sua empresa. Ele
tambem acompanha o instalador do BioMini.

## Onde colocar

Os tres aqui, em `libs/`. O `.csproj` cuida do resto: referencia o wrapper e
copia `UFScanner.dll` e `UFLicense.dat` para o lado do `.exe` no build — o SDK
carrega esses dois **pelo nome, a partir do diretorio do executavel**, entao
deixar so em `libs/` nao basta.

## Sem eles

O projeto **nao compila** (`HintPath` nao resolve) e o workflow para na
primeira etapa, de proposito, com a mensagem apontando para este arquivo.

Para desenvolver sem leitor e sem SDK, use o `simulador.py` na raiz: ele sobe
na mesma porta e responde no mesmo formato, com uma digital fixa.
