# Serviço de ditado do Notchy

O Notchy transcreve o ditado com um modelo de fala de **pesos abertos que roda na sua máquina**. Por padrão é o
[Qwen3-ASR-1.7B](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), em **português do Brasil (pt-BR)**. Não há API paga
nem chave, e nenhuma API paga entra como plano B escondido.

Este serviço fica **separado da interface**. Os apps do Notchy (Mac, Windows e Linux) mandam o áudio do microfone
para ele e recebem o texto. Por isso dá para trocar o modelo, ou rodar o serviço numa máquina com GPU da rede, sem
mexer nos apps.

```
Notchy  ──WebSocket /v1/dictation (PCM 16 bits, 16 kHz, mono)──▶  serviço  ──▶  Qwen3-ASR (vLLM ou Transformers)
                                                                           └──▶  Voxtral Realtime (comparação)
```

## Requisitos de hardware

| Como roda | Texto parcial enquanto fala | O que precisa |
|---|---|---|
| **Qwen3-ASR + vLLM** (streaming oficial) | sim, atualiza a cada 1 s | Linux (ou Windows pelo WSL2) com **GPU NVIDIA e CUDA**. O vLLM não tem versão para GPU no macOS nem no Windows nativo. |
| **Qwen3-ASR + Transformers** | não: o texto aparece ao parar de falar | GPU NVIDIA (CUDA), **Mac com Apple silicon (MPS)** ou só CPU (bem mais lento). |
| **Voxtral Mini 4B Realtime** (comparação) | sim | GPU NVIDIA com **16 GB ou mais** (cartão do modelo), vLLM nightly. Não roda em CPU nem em Apple silicon por esse caminho. |

Números **medidos** neste projeto, num MacBook Pro M3 Pro com 18 GB, backend Transformers no MPS, float16:
- **Carregar o modelo:** cerca de 20 s.
- **Transcrever 4 a 8 s de fala:** 1,4 a 3,0 s depois de parar.
- **float32:** o mesmo texto, com o dobro do tempo.
- **Modelo frio:** parado por 2 minutos, o modelo esfria, e a primeira transcrição levou 24 s. Por isso o serviço:
  - aquece o modelo ao carregar;
  - aquece de novo no começo de cada ditado, enquanto a pessoa fala;
  - no Apple silicon, roda meio segundo de silêncio a cada 30 s sem uso (`DICTATION_KEEP_WARM_SECONDS`).

Números **documentados**:
- **Pesos:** 4,7 GB em BF16 (arquivos do repositório no Hugging Face).
- **Voxtral:** 8,9 GB de pesos e "uma GPU com ≥ 16 GB".
- **O que não é documentado:** a VRAM exigida pelo Qwen3-ASR-1.7B. Pelos pesos, uma GPU de 8 GB deve bastar, mas
  isso é **estimativa**, não medição. O vLLM reserva `DICTATION_GPU_MEMORY_UTILIZATION` (0,8) da memória da GPU.

## Instalação rápida

```bash
cd dictation-service
./scripts/start.sh            # macOS e Linux
```

```powershell
cd dictation-service
.\scripts\start.ps1           # Windows
```

Na primeira vez, o script:
- cria `.venv` e instala o serviço com o Qwen3-ASR (o PyTorch e outros, cerca de 2 GB);
- usa o vLLM se for Linux com `nvidia-smi`;
- baixa os pesos (4,7 GB) para o cache do Hugging Face (`~/.cache/huggingface`).

O serviço fica em `http://127.0.0.1:8765`. Para confirmar:

```bash
curl http://127.0.0.1:8765/health
```

`"ready": true` quer dizer que o modelo carregou. `"streaming"` diz se haverá texto parcial. Se `"status"` for
`"error"`, o campo `"error"` explica o que falta.

Para checar a máquina sem subir o servidor (carrega o modelo, transcreve e sai):

```bash
./scripts/start.sh --check                  # 1 s de silêncio
./scripts/start.sh --check gravacao.wav     # um arquivo seu
```

## Instalação manual

O Qwen3-ASR recomenda o **Python 3.12**. O serviço aceita do 3.10 em diante.

### Linux com GPU NVIDIA (streaming)

```bash
cd dictation-service
python3.12 -m venv .venv && source .venv/bin/activate
pip install -e ".[qwen-vllm]"     # qwen-asr[vllm] 0.0.6, que fixa vllm==0.14.0
DICTATION_BACKEND=vllm python -m notchy_dictation
```

O README do Qwen3-ASR também mostra o vLLM *nightly*, com rodas cu129, se você precisar de uma versão mais nova:

```bash
uv pip install -U vllm --pre --extra-index-url https://wheels.vllm.ai/nightly/cu129 \
  --extra-index-url https://download.pytorch.org/whl/cu129 --index-strategy unsafe-best-match
uv pip install "vllm[audio]"
```

Com o vLLM, o modelo carrega **antes** de a porta abrir, como no demo oficial de streaming. O `/health` só responde
quando ele está pronto.

### macOS com Apple silicon

```bash
cd dictation-service
python3.12 -m venv .venv && source .venv/bin/activate
pip install -e ".[qwen]"
PYTORCH_ENABLE_MPS_FALLBACK=1 python -m notchy_dictation
```

O backend Transformers usa o MPS com float16. O texto chega inteiro ao parar de falar.

### Windows

- **Nativo (Transformers):** `.\scripts\start.ps1`. Com GPU NVIDIA, instale antes o PyTorch com CUDA
  (`.venv\Scripts\python -m pip install torch --index-url https://download.pytorch.org/whl/cu129`). Sem ela, roda na CPU.
- **Streaming:** use o WSL2 com Ubuntu e o driver NVIDIA para WSL, e siga "Linux com GPU NVIDIA" dentro dele. O
  Windows encaminha `127.0.0.1:8765` do WSL2 para o Notchy sozinho.

### Baixar os pesos antes

```bash
hf download Qwen/Qwen3-ASR-1.7B           # 4,7 GB, vai para ~/.cache/huggingface
```

Depois disso o serviço funciona sem internet. Use `HF_HUB_OFFLINE=1` para garantir que ele nem tente a rede. Também
dá para apontar para uma pasta: `DICTATION_MODEL=/caminho/para/Qwen3-ASR-1.7B`.

## Configuração

Copie `.env.example` para `.env`. Nada ali é secreto. O ambiente vale mais que o `.env`, e o `.env` mais que os padrões.

| Variável | Padrão | O que faz |
|---|---|---|
| `DICTATION_HOST` / `DICTATION_PORT` | `127.0.0.1` / `8765` | onde o serviço escuta |
| `DICTATION_PROVIDER` | `qwen3-asr` | ou `voxtral-realtime` |
| `DICTATION_MODEL` | `Qwen/Qwen3-ASR-1.7B` | id no Hugging Face ou pasta local (o `Qwen/Qwen3-ASR-0.6B` é menor) |
| `DICTATION_BACKEND` | `auto` | `vllm` (streaming), `transformers` (offline) ou `auto` |
| `DICTATION_DEVICE` / `DICTATION_DTYPE` | `auto` | só no Transformers: `cuda:0`, `mps`, `cpu`; `bfloat16`, `float16`, `float32` |
| `DICTATION_LANGUAGE` | `pt-BR` | idioma do reconhecimento (o Qwen3-ASR recebe `Portuguese`) |
| `DICTATION_CHUNK_SECONDS`, `DICTATION_UNFIXED_CHUNKS`, `DICTATION_UNFIXED_TOKENS` | `1.0`, `4`, `5` | streaming, com os valores do demo oficial de microfone |
| `DICTATION_CONTEXT` | vazio | nomes e siglas que o modelo deve esperar, como `Notchy, Mochi` |
| `DICTATION_MAX_SECONDS` | `300` | duração máxima de um ditado |
| `DICTATION_KEEP_WARM_SECONDS` | `-1` | manter o modelo aquecido: automático (a cada 30 s no Apple silicon), `0` desliga |
| `VOXTRAL_URL` / `VOXTRAL_MODEL` | `ws://127.0.0.1:8000/v1/realtime` / `mistralai/Voxtral-Mini-4B-Realtime-2602` | o servidor do Voxtral |

O endereço do serviço se escolhe no Notchy, em **Configurações › Ditado › Endereço do serviço**.

## Testar falando em português

1. Inicie o serviço e espere `ready:` no terminal (ou `"ready": true` no `/health`).
2. No Notchy, abra **Configurações › Ditado**:
   - ligue o ditado;
   - clique em **Testar conexão**: deve aparecer "Qwen3-ASR-1.7B · …";
   - conceda o microfone e a acessibilidade quando o sistema pedir.
3. Abra um editor de texto, **segure a tecla do ditado** (fn no Mac, Alt direito no Windows/Linux) e diga, por
   exemplo: *"Amanhã às nove horas vamos revisar o relatório com a equipe."* Solte a tecla. O texto aparece no card
   do notch e é colado onde está o cursor.
4. Ou use o botão: abra **Ditado** no menu do Notchy, clique em **Gravar**, fale e clique em **Parar**. Depois edite
   ou copie o texto no card.

Sem o app, grave um WAV e mande para o serviço:

```bash
# macOS: grave com o QuickTime (Arquivo › Nova Gravação de Áudio), depois converta
afconvert -f WAVE -d LEI16@16000 -c 1 gravacao.m4a gravacao.wav

curl -X POST --data-binary @gravacao.wav -H "Content-Type: audio/wav" http://127.0.0.1:8765/v1/transcribe

# o mesmo caminho dos apps (WebSocket, quadros de 100 ms no ritmo da fala, textos parciais se houver)
.venv/bin/python -m notchy_dictation.client gravacao.wav
```

Para uma frase de teste sem microfone, use a voz do sistema:
`say -v Luciana -o teste.wav --file-format=WAVE --data-format=LEI16@16000 "Olá, este é um teste."`

As vozes Eddy, Flo, Reed e as outras "Eloquence" são robóticas demais: o modelo erra muito nelas, e isso não reflete
uma voz de verdade.

## Qwen3-ASR × Voxtral Realtime

O Voxtral fica como **alternativa de comparação** para ditado ao vivo. O principal continua o Qwen3-ASR.

| | Qwen3-ASR-1.7B | Voxtral Mini 4B Realtime 2602 |
|---|---|---|
| **Qualidade em português** | Não há WER só de pt. Portuguese entra nas médias: MLS 8,55, Common Voice 9,18, Fleurs 4,90 (12 idiomas). Média offline 2,69 e streaming 3,33 (cartão do modelo). | Fleurs pt: 5,03 % com atraso de 480 ms, 3,93 % com 2,4 s, 10,01 % com 160 ms (cartão do modelo). |
| **Latência do texto parcial** | Um novo parcial a cada `DICTATION_CHUNK_SECONDS` (1 s), relendo todo o áudio. | Atraso configurável de 80 ms a 2,4 s (padrão 480 ms), com texto incremental. |
| **Requisitos** | 4,7 GB de pesos. Streaming só com vLLM (CUDA). Offline também roda em Apple silicon e CPU. | 8,9 GB de pesos, uma GPU com 16 GB ou mais, vLLM nightly. Só CUDA. |
| **Idiomas** | 30 idiomas e 22 dialetos chineses. Não separa pt-BR de pt-PT. | 13 idiomas, incluindo português. |
| **Licença** | Apache-2.0 | Apache-2.0 |

O Qwen continua como principal por três motivos:
- roda em mais máquinas (Mac e CPU, inclusive);
- tem metade do tamanho;
- tem streaming oficial pelo próprio pacote.

O Voxtral pode ganhar na latência do parcial, mas só numa GPU grande. Os números acima são os publicados pelos
autores. Não medi nenhum dos dois em GPU neste projeto, porque a máquina de desenvolvimento não tem NVIDIA.

Para comparar, suba o Voxtral numa GPU, conforme o cartão do modelo:

```bash
uv pip install -U vllm && uv pip install soxr librosa soundfile
VLLM_DISABLE_COMPILE_CACHE=1 vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 \
  --compilation_config '{"cudagraph_mode": "PIECEWISE"}'
```

Depois, rode este serviço apontando para ele:

```bash
DICTATION_PROVIDER=voxtral-realtime VOXTRAL_URL=ws://127.0.0.1:8000/v1/realtime ./scripts/start.sh
```

Os apps não mudam nada: o card mostra "Voxtral…" no lugar de "Qwen3-ASR…".

## Protocolo

O protocolo está todo em `src/notchy_dictation/protocol.py`. O arquivo `tests/fixtures/dictation.json`, na raiz do
repositório, tem os casos que os três lados testam.

- **Cliente:**
  1. manda `{"type":"start","language":"pt-BR","sample_rate":16000,"encoding":"pcm_s16le","channels":1}`;
  2. manda quadros binários de PCM;
  3. termina com `{"type":"stop"}`, ou desiste com `{"type":"cancel"}`.
- **Serviço:**
  - `ready`, com o modelo, o backend e se há `streaming`;
  - `partial`, com o **texto inteiro até agora**, que substitui o anterior para nada repetir;
  - `final`, com o texto, `audio_ms` e `processing_ms`;
  - `error`, com um código estável e uma mensagem.
- **Fim da fala:** o app grava mais 250 ms depois de você soltar a tecla. O serviço só responde o `final` depois de
  ouvir tudo o que chegou antes do `stop`, e o `finish_streaming_transcribe` do Qwen processa o pedaço final que não
  completou um bloco. Assim as últimas palavras não se perdem.
- **Silêncio não vira texto:** os modelos de fala inventam palavras no silêncio (o Qwen3-ASR transformou meio
  segundo de nada em "Então"). O serviço só manda o áudio ao modelo se algum trecho de 30 ms passar de cerca de
  -48 dBFS.
- **Formatação:** o Qwen3-ASR já pontua. O serviço só ajeita espaços e a maiúscula de início de frase, sem trocar,
  tirar ou acrescentar palavras.

## Privacidade e segurança

- **O áudio nunca vai para o disco.** Ele fica na memória durante o ditado e some ao terminar. O log registra a
  duração de cada ditado, nunca o texto.
- **Só este computador, por padrão.** O serviço escuta em `127.0.0.1`. Ele recusa qualquer requisição com
  cabeçalho `Origin`, então nenhuma página aberta no navegador consegue usá-lo. Os apps do Notchy não mandam esse
  cabeçalho. `DICTATION_ALLOWED_ORIGINS` libera origens específicas, se um dia for preciso.
- **Sem senha:** com `DICTATION_HOST=0.0.0.0`, qualquer máquina da rede pode mandar áudio. Use só numa rede em que
  você confia, ou faça um túnel SSH (`ssh -L 8765:127.0.0.1:8765 maquina-gpu`).

## Problemas comuns

- **`"status": "error"` com "precisa de uma GPU NVIDIA":** você pediu `DICTATION_BACKEND=vllm` numa máquina sem
  CUDA. Use `transformers`.
- **No Mac, um ditado depois de muito tempo parado demora:** o modelo esfria. O serviço o mantém aquecido a cada
  30 s. Se você desligou isso (`DICTATION_KEEP_WARM_SECONDS=0`), a primeira transcrição pode levar uns 20 s.
- **O Notchy diz "Serviço local offline":** o serviço não está rodando, ou o endereço nas Configurações está
  diferente. O padrão é `http://127.0.0.1:8765`.
- **Nomes próprios saem errados:** ponha-os em `DICTATION_CONTEXT`.

## Testes

```bash
bash scripts/test-dictation-service.sh     # na raiz do repositório
```

Os testes rodam sem modelo e sem GPU, com dublês que seguem o contrato do `qwen-asr`. O teste com o modelo de
verdade é o roteiro "Testar falando em português" acima.
