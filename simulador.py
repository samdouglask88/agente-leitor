"""Simulador do agente de leitura de digital.

Existe por um motivo pratico: o agente de verdade so roda no Windows (as
bibliotecas da Suprema sao nativas de 32 bits e nao ha versao Linux em maos),
mas o desenvolvimento do sistema acontece no Linux. Sem isto, qualquer
mexida na tela de coleta so podia ser testada em outra maquina, com leitor
espetado e alguem disponivel para encostar o dedo.

Ele responde exatamente como o agente real, na mesma porta e no mesmo
endereco, e devolve um template de digital DE VERDADE — um dos capturados nos
testes com equipamento real. Serve para exercitar a tela, o salvamento e o
envio ao equipamento de ponta a ponta.

NAO substitui o teste com leitor: so o agente real prova que a captura
funciona. Isto prova que todo o resto funciona.

Uso:
    python3 agente-leitor/simulador.py                 # sucesso, dedo valido
    python3 agente-leitor/simulador.py --sem-leitor    # simula leitor ausente
    python3 agente-leitor/simulador.py --timeout       # simula ninguem encostando
    python3 agente-leitor/simulador.py --porta 5010

Depois abra o sistema NO NAVEGADOR DESTA MESMA MAQUINA — a tela chama
localhost, entao navegador e agente (ou simulador) precisam estar juntos.
"""
import argparse
import base64
import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

# Slot fixo do formato Suprema 2001. O agente real nunca corta o template para
# o tamanho real: o destino exige os 384 bytes com zeros no fim.
SLOT_SUPREMA_2001 = 384

# Templates reais, capturados em equipamento de verdade durante a investigacao
# do Henry. Usar um deles deixa o dado do banco parecido com producao.
CANDIDATOS_TEMPLATE = [
    "../../henry-primme-sf/templates-lidos/matricula-1-dedo-0.bin",
    "../../henry-primme-sf/templates-lidos/matricula-999-dedo-0.bin",
    "../../henry-primme-sf/templates-lidos/dummy-384.bin",
]


def carregar_template():
    """Devolve 384 bytes de template. Cai para bytes aleatorios se nao achar.

    O arquivo de verdade vive em outro repositorio, que nem todo mundo tem
    clonado. Falhar aqui deixaria o simulador inutil justamente para quem mais
    precisa dele, entao ha um plano B — que serve para exercitar a tela, mas
    nao para gravar em equipamento real.
    """
    base = os.path.dirname(os.path.abspath(__file__))
    for relativo in CANDIDATOS_TEMPLATE:
        caminho = os.path.normpath(os.path.join(base, relativo))
        if os.path.isfile(caminho):
            with open(caminho, "rb") as f:
                dados = f.read()
            print(f"Template real carregado de {caminho} ({len(dados)} bytes)")
            return dados[:SLOT_SUPREMA_2001].ljust(SLOT_SUPREMA_2001, b"\x00")

    print("AVISO: nenhum template real encontrado; gerando bytes aleatorios.")
    print("       Serve para testar a tela, NAO para gravar em equipamento.")
    return bytes(random.getrandbits(8) for _ in range(SLOT_SUPREMA_2001))


class Handler(BaseHTTPRequestHandler):
    template = b""
    modo = "ok"

    def _responder(self, corpo, codigo=200):
        # Mesma razao do agente real: a tela vem do servidor e o simulador
        # responde de localhost. Sem este cabecalho o navegador bloqueia.
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_OPTIONS(self):
        self._responder({})

    def do_GET(self):
        caminho = self.path.split("?")[0]

        if caminho == "/api/status.json":
            leitores = 0 if self.modo == "sem-leitor" else 1
            self._responder({"status": "OK", "leitores": leitores})
            return

        if caminho != "/api/capture.json":
            self._responder({"status": f"Endereco desconhecido: {caminho}"}, 404)
            return

        if self.modo == "sem-leitor":
            self._responder(
                {"status": "Nenhum leitor encontrado. Espete o leitor e confira o driver."}
            )
            return

        if self.modo == "timeout":
            # O agente real espera 15s pelo dedo; aqui bastam 3 para ver a
            # tela se comportar sem testar a paciencia de ninguem.
            time.sleep(3)
            self._responder({"status": "Tempo esgotado. Ninguem encostou o dedo no leitor."})
            return

        # O envelope "1{" e o que o fingerprint.py espera: ele descarta tudo
        # ate a primeira chave e usa o que vem depois.
        corpo = b"1{" + self.template
        print("Digital entregue (simulada).")
        self._responder(
            {
                "status": "OK",
                "template": base64.b64encode(corpo).decode("ascii"),
                "qualidade": random.randint(60, 95),
            }
        )

    def log_message(self, formato, *args):
        print(f"{self.address_string()} — {formato % args}")


def main():
    p = argparse.ArgumentParser(description="Simulador do agente de leitura de digital")
    p.add_argument("--porta", type=int, default=5009)
    p.add_argument("--sem-leitor", action="store_true", help="responde como se nao houvesse leitor")
    p.add_argument("--timeout", action="store_true", help="responde como se ninguem encostasse o dedo")
    args = p.parse_args()

    Handler.template = carregar_template()
    if args.sem_leitor:
        Handler.modo = "sem-leitor"
    elif args.timeout:
        Handler.modo = "timeout"

    servidor = HTTPServer(("127.0.0.1", args.porta), Handler)
    print(f"Simulador no ar em http://localhost:{args.porta}/  (modo: {Handler.modo})")
    print("Abra o sistema no navegador DESTA maquina e clique em Ler.")
    print("Ctrl+C para encerrar.")
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrado.")


if __name__ == "__main__":
    main()
