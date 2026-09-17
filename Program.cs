// Agente de leitura de digital do UltraAcesso.
//
// O navegador nao consegue acender um leitor USB sozinho. Por isso a tela de
// cadastro de funcionario (form_modal_funcionario.js) chama
// http://localhost:5009/api/capture.json e espera que ALGUEM na maquina do
// operador atenda. Esse alguem e este programa.
//
// Ate agora esse programa nao existia em lugar nenhum: a chamada dava
// ERR_CONNECTION_REFUSED, o JavaScript estourava em seguida e o botao "Ler"
// simplesmente nao fazia nada - sem mensagem, sem log, sem pista.
//
// So roda no Windows, como x86: as bibliotecas nativas da Suprema (UFScanner)
// sao de 32 bits. Precisa do driver do leitor instalado.
//
// Uso:
//   AgenteLeitor.exe [porta]        (porta padrao 5009)

using System;
using System.Net;
using System.Text;
using Suprema;

internal static class Program
{
    private const int PORTA_PADRAO = 5009;

    // Slot fixo do formato Suprema 2001. O Extract() devolve template de
    // tamanho VARIAVEL (342 e 332 bytes foram vistos num BioMini Plus 2), mas
    // o destino espera o slot inteiro de 384 com zeros no fim. Cortar para o
    // tamanho real faz o equipamento recusar a gravacao.
    private const int SLOT_SUPREMA_2001 = 384;
    private const int TIPO_TEMPLATE_SUPREMA_2001 = 2001;

    // Sem limite, o CaptureSingleImage fica preso esperando dedo para sempre e
    // a requisicao do navegador nunca termina.
    private const int TIMEOUT_CAPTURA_MS = 15000;

    private const int QUALIDADE_MINIMA_AVISO = 50;

    private static UFScannerManager _manager;

    private static int Main(string[] args)
    {
        int porta = PORTA_PADRAO;
        if (args.Length > 0 && int.TryParse(args[0], out int informada))
        {
            porta = informada;
        }

        Console.WriteLine("Agente de leitura de digital - UltraAcesso");
        Console.WriteLine("Inicializando o SDK da Suprema...");

        _manager = new UFScannerManager(null);
        UFS_STATUS status = _manager.Init();
        if (status != UFS_STATUS.OK)
        {
            Console.WriteLine($"ERRO: falha ao inicializar o SDK: {status}");
            Console.WriteLine("Confira se as DLLs estao na mesma pasta do executavel.");
            return 1;
        }

        Console.WriteLine(_manager.Scanners.Count == 0
            ? "AVISO: nenhum leitor encontrado agora (vou procurar de novo a cada leitura)."
            : $"Leitor encontrado: {_manager.Scanners[0].ID}");

        var listener = new HttpListener();
        // So "localhost": esse prefixo o Windows libera sem precisar de
        // administrador, e e exatamente o endereco que a tela chama.
        listener.Prefixes.Add($"http://localhost:{porta}/");

        try
        {
            listener.Start();
        }
        catch (HttpListenerException e)
        {
            Console.WriteLine($"ERRO: nao consegui escutar na porta {porta}: {e.Message}");
            Console.WriteLine("Outro programa pode estar usando essa porta.");
            return 1;
        }

        Console.WriteLine($"No ar em http://localhost:{porta}/");
        Console.WriteLine("Deixe esta janela aberta enquanto usar o cadastro de digitais.");
        Console.WriteLine("Para encerrar, feche a janela ou aperte Ctrl+C.");

        while (listener.IsListening)
        {
            HttpListenerContext ctx;
            try
            {
                ctx = listener.GetContext();
            }
            catch (Exception)
            {
                break;
            }

            try
            {
                Atender(ctx);
            }
            catch (Exception e)
            {
                Console.WriteLine($"Erro ao atender requisicao: {e.Message}");
                try
                {
                    Responder(ctx, Json("Erro interno no agente: " + Escapar(e.Message)));
                }
                catch
                {
                    // Conexao ja caiu; nada a fazer.
                }
            }
        }

        _manager.Uninit();
        return 0;
    }

    private static void Atender(HttpListenerContext ctx)
    {
        string caminho = ctx.Request.Url.AbsolutePath;

        if (ctx.Request.HttpMethod == "OPTIONS")
        {
            Responder(ctx, "");
            return;
        }

        switch (caminho)
        {
            case "/api/capture.json":
                Responder(ctx, Capturar());
                return;

            // Serve para conferir se o agente esta no ar sem precisar encostar
            // o dedo - o primeiro teste de quem esta instalando.
            case "/api/status.json":
                int leitores = _manager.Scanners.Count;
                Responder(ctx, "{\"status\":\"OK\",\"leitores\":" + leitores + "}");
                return;

            default:
                ctx.Response.StatusCode = 404;
                Responder(ctx, Json("Endereco desconhecido: " + Escapar(caminho)));
                return;
        }
    }

    private static string Capturar()
    {
        // O leitor pode ter sido espetado depois que o agente subiu, ou
        // reconectado numa porta diferente. Reenumerar aqui evita obrigar o
        // operador a reiniciar o programa.
        if (_manager.Scanners.Count == 0)
        {
            ReenumerarLeitores(_manager);
        }

        if (_manager.Scanners.Count == 0)
        {
            return Json("Nenhum leitor encontrado. Espete o leitor e confira o driver.");
        }

        UFScanner scanner = _manager.Scanners[0];
        scanner.nTemplateType = TIPO_TEMPLATE_SUPREMA_2001;
        scanner.DetectCore = false;
        DefinirTimeout(scanner, TIMEOUT_CAPTURA_MS);

        Console.WriteLine("Aguardando dedo no leitor...");

        UFS_STATUS status = scanner.CaptureSingleImage();
        if (status == UFS_STATUS.TIMEOUT)
        {
            return Json("Tempo esgotado. Ninguem encostou o dedo no leitor.");
        }
        if (status != UFS_STATUS.OK)
        {
            return Json("Falha ao capturar: " + status);
        }

        byte[] buffer = new byte[SLOT_SUPREMA_2001];
        status = scanner.Extract(buffer, out int tamanho, out int qualidade);
        if (status != UFS_STATUS.OK)
        {
            return Json("Falha ao extrair a digital: " + status);
        }

        Console.WriteLine($"Capturado: qualidade {qualidade}, template real {tamanho} bytes.");
        if (qualidade < QUALIDADE_MINIMA_AVISO)
        {
            Console.WriteLine("AVISO: qualidade baixa. Dedo seco ou mal posicionado.");
        }

        // O buffer inteiro de 384 bytes vai, com os zeros de padding no fim.
        // Nada de cortar para `tamanho`.
        //
        // O "1{" na frente e o envelope que o UltraAcesso espera: em
        // fingerprint.py, to_henry_format joga fora tudo ate a primeira chave
        // e usa o que vem depois.
        byte[] envelope = Encoding.ASCII.GetBytes("1{");
        byte[] corpo = new byte[envelope.Length + SLOT_SUPREMA_2001];
        Buffer.BlockCopy(envelope, 0, corpo, 0, envelope.Length);
        Buffer.BlockCopy(buffer, 0, corpo, envelope.Length, SLOT_SUPREMA_2001);

        string template = Convert.ToBase64String(corpo);
        return "{\"status\":\"OK\",\"template\":\"" + template + "\",\"qualidade\":" + qualidade + "}";
    }

    // O wrapper da Suprema e de 2012 e nao ha documentacao dele por aqui.
    // Estas duas capacidades - limitar o tempo de espera e reenumerar os
    // leitores - nao aparecem em nenhum codigo que ja tenha sido compilado
    // contra essa DLL, entao nao ha prova de que existam com esse nome.
    //
    // Chamar por reflexao faz o programa compilar de qualquer jeito: se o
    // membro existir, o recurso funciona; se nao existir, perde-se so o
    // recurso, em vez de nao haver programa nenhum. Com um leitor na mao da
    // para trocar por chamada direta e apagar isto.
    private static void DefinirTimeout(object scanner, int ms)
    {
        try
        {
            var prop = scanner.GetType().GetProperty("Timeout");
            if (prop != null && prop.CanWrite)
            {
                prop.SetValue(scanner, ms, null);
                return;
            }
            Console.WriteLine("AVISO: este SDK nao aceita limite de tempo; a espera pelo dedo nao tem prazo.");
        }
        catch (Exception e)
        {
            Console.WriteLine($"AVISO: nao consegui definir o limite de tempo: {e.Message}");
        }
    }

    private static void ReenumerarLeitores(object manager)
    {
        try
        {
            var metodo = manager.GetType().GetMethod("UpdateScannerList", Type.EmptyTypes)
                      ?? manager.GetType().GetMethod("Update", Type.EmptyTypes);
            if (metodo != null)
            {
                metodo.Invoke(manager, null);
                return;
            }
            Console.WriteLine("AVISO: este SDK nao reenumera leitores; espete o leitor antes de abrir o agente.");
        }
        catch (Exception e)
        {
            Console.WriteLine($"AVISO: nao consegui reprocurar o leitor: {e.Message}");
        }
    }

    // A tela mostra este texto direto para o operador (o JavaScript joga
    // item.status na tela), entao a mensagem precisa fazer sentido para quem
    // esta na recepcao, nao para quem programou.
    private static string Json(string mensagem)
    {
        return "{\"status\":\"" + mensagem + "\"}";
    }

    private static string Escapar(string texto)
    {
        return texto.Replace("\\", "\\\\").Replace("\"", "'").Replace("\n", " ").Replace("\r", " ");
    }

    private static void Responder(HttpListenerContext ctx, string corpo)
    {
        // A tela do UltraAcesso e servida de outro endereco (o servidor), e o
        // agente responde de localhost: para o navegador sao origens
        // diferentes. Sem este cabecalho ele bloqueia a resposta e o operador
        // ve o mesmo "nao acontece nada" de antes.
        ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*");
        ctx.Response.ContentType = "application/json; charset=utf-8";

        byte[] bytes = Encoding.UTF8.GetBytes(corpo);
        ctx.Response.ContentLength64 = bytes.Length;
        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
        ctx.Response.OutputStream.Close();
    }
}
