# Relatório técnico — Membro 3 (workloads complexos + McPAT)

Registro do que foi feito, do que falhou e por quê, do que foi medido e do que falta.
A explicação conceitual está em [`GUIA_MEMBRO3.md`](GUIA_MEMBRO3.md); versões e origens dos
fontes em [`../benchmarks/VERSIONS.md`](../benchmarks/VERSIONS.md).

Última atualização: 2026-10-12.

> Todos os números deste documento vêm de execuções `--size test` (entradas reduzidas, uma
> repetição). Servem para mostrar que o fluxo funciona. **Nenhum deles é resultado do artigo.**

---

## 1. Estado atual

| Item | Estado |
|---|---|
| Imagem Docker com Sniper 8.1 + 3 correções | pronta (`larc-thermal-sniper:latest`, `173130a4f97b`) |
| Fontes dos 3 workloads, com patches de ROI | prontos (`benchmarks/fetch_workloads.sh`) |
| Binários (`benchmarks/bin-m3/`) | `mg.S.x`, `mg.W.x`, `mg.B.x`, `XSBench`, `matvecsplit` |
| Fluxo nativo → Sniper → validação → McPAT → `summary.json` | funciona para MG, MatVecSplit e XSBench |
| Cenários já exercitados | os quatro: `a64fx_s`, `a64fx32`, `larc_c`, `larc_a` (nem todo workload em todo cenário; ver seção 3) |
| Tamanho `mid` | nunca executado |
| Campanha `full` (3 workloads × 4 cenários × 3 repetições = 36 execuções) | **não iniciada** |
| Nada disso está em commit | tudo ainda é alteração local (`git status`) |

---

## 2. Problemas encontrados e correções

### 2.1 No Sniper (corrigidos em `docker/Dockerfile`)

| # | Sintoma | Causa | Correção |
|---|---|---|---|
| 1 | benchmark em C que inclui `sim_api.h` não compila | o cabeçalho inclui `<unordered_map>` (C++) sem guarda | guarda `#ifdef __cplusplus` |
| 2 | aborta em `memory_manager.cc:391` ("Tag directories may only be at 'master' node") em qualquer configuração com cache compartilhada | `m_tag_directory_present` nunca é inicializado no construtor | inicializar com `false` |
| 3 | `*ERROR* We cannot execute instructions while not on a core` / "No cores available for spawnThread"; `run-sniper` sai com 134 | o gravador SIFT registra uma thread na entrada de `clone3`; sob o SDE o `clone3` falha e a glibc repete com `clone`, que registra de novo: N threads viram N+1 | não registrar nada na entrada de `clone3` |
| 4 | `Segmentation fault` em `coreInitiateMemoryAccess` no início de simulações de 32 threads; sai com 139 | `TraceManager::getTraceThread()` lê `m_threads` sem trava enquanto `newThread()` faz `push_back` (realocação do vetor) | `m_threads.reserve(4096)` no construtor |

Cada correção é uma camada própria do Dockerfile, com `grep` logo depois do `sed`: se o padrão
deixar de existir numa versão futura do Sniper, o *build* da imagem falha em vez de seguir sem a
correção. `./scripts/check_env.sh` confere as três na imagem pronta.

### 2.1-b Defeito do Sniper contornado, não corrigido (2026-10-12)

`trace_thread.cc:pinTraceThreadToCPU` deveria espalhar as threads de simulação pelas CPUs do
hospedeiro. Na prática a primeira thread se fixa na CPU 0 e as seguintes herdam essa afinidade:
**toda a simulação roda numa única CPU do hospedeiro, sempre a 0**. Uma simulação sozinha não
sofre; várias em paralelo dividem a CPU 0 (medido: 7 simulações a ~15% de CPU cada, com a máquina
85% ociosa). Contorno: `M3_CPUSET=<cpus>` (`scripts/common.sh`) dá a cada execução um conjunto
próprio de CPUs. Testado com duas execuções em paralelo (`0-3` e `4-7`): MatVecSplit em 32 núcleos
levou 434 s, contra 1.081 s quando dividia a CPU 0 com outra simulação.

Outro limite prático: memória. Sete simulações mais navegador esgotaram os 13 GiB do notebook e
os processos foram encerrados pelo sistema. Rodar no máximo duas ou três por vez.

### 2.2 Na configuração dos cenários

- **Escalonador** (`configs/larc_base.cfg`): o `base_system_sniperspace.cfg` usa `static`, que
  aborta quando há mais threads do que núcleos. Passou para `pinned`.
- **Teste preliminar** (`scripts/run_preliminary_test.sh`): o Sniper 8.x exige um esquema de
  tradução de endereços explícito; acrescentado `-c address_translation_schemes/baseline`.

### 2.3 Nos workloads e scripts

| Sintoma | Causa | Correção |
|---|---|---|
| `cp: cannot create regular file 'bin/mg.S.x': Permission denied` | `benchmarks/bin/` foi criado por um contêiner rodando como root | binários do Membro 3 vão para `benchmarks/bin-m3/`; os scripts rodam o contêiner com o UID do host |
| MG simulado termina com código 0, mas sem a linha `VERIFICATION SUCCESSFUL` | sob o Sniper o processo é encerrado antes de o gfortran descarregar o buffer de saída | `GFORTRAN_UNBUFFERED_ALL=1` (só afeta E/S, que está fora da ROI) |
| `tools/mcpat.py` aborta com `KeyError: 'L1-D.loads'` | o Sniper 8.1 grava `tloads`, `tstores`, `tload-misses`…; o `mcpat.py` ainda procura os nomes antigos | `scripts/mcpat_sniper.py` cria os apelidos e reaproveita o `mcpat.py` original |
| XSBench sai com código 1 e "INVALID CHECKSUM" | o hash de referência embutido só existe para o número padrão de lookups | aceita-se código 0 ou 1; a validação é checksum simulado == checksum nativo |

### 2.4 Dois defeitos nossos, corrigidos em 2026-10-12

**(a) Componentes de potência sumiam do `summary.json`.** O `mcpat.py` junta em `other` todo
componente abaixo de 1% do total (o limiar existe para o gráfico de barras dele). Como o limiar é
aplicado em cada recorte (estática, dinâmica, total, pico) separadamente, o conjunto de
componentes mudava de um recorte para outro. Efeito observado antes da correção:

| Execução | Campo | Antes | Depois |
|---|---|---|---|
| matvecsplit / a64fx_s | L2 dinâmica | 0,000 W | 0,232 W |
| matvecsplit / a64fx_s | lógica dinâmica | 31,081 W | 30,849 W |
| mg / a64fx_s | L2 de pico | 0,000 W | 2,814 W |
| mg / larc_a | lógica de pico | 793,98 W | 789,71 W (a DRAM estava somada à lógica) |

Ou seja, a potência da L2 era contada como lógica justamente nos casos de L2 pequena. A correção
(`scripts/mcpat_sniper.py`) chama o `power_stack` com `nocollapse=True`: todos os componentes
aparecem sempre, cada um com o seu valor. Os totais não mudam; só a repartição. Os três
`summary.json` existentes foram regerados; a saída anterior do McPAT ficou em `mcpat.prev_*`.

**(b) Fração de núcleo ocupado acima de 1.** Alguns núcleos saíam com 1,01–1,02. Os relógios
locais dos núcleos não estão alinhados com o tempo global na entrada da ROI, então o tempo ocioso
calculado pode ficar ligeiramente negativo (até ~1,5% da ROI nos testes). `result_summary.py`
agora limita o valor a [0, 1].

---

> **Atualização de 2026-10-12 (tarde):** a lista abaixo cobre até a manhã. As execuções
> posteriores (XSBench e MatVecSplit nos quatro cenários) e as tabelas consolidadas estão em
> [`RESULTADOS_PRELIMINARES.md`](RESULTADOS_PRELIMINARES.md) e em `results/entrega/`.

## 3. Execuções realizadas

Todas `--size test`, repetição 1. Diretórios em `results/<workload>/<cenário>/`.

| Execução | Resultado | Observação |
|---|---|---|
| mg / a64fx_s / `test_20261011_214956` | FALHOU (rc 134) | defeito nº 3 (thread fantasma), antes da correção |
| mg / a64fx_s / `test_20261011_220113` | FALHOU | sem linha de verificação (buffer do gfortran) |
| mg / a64fx_s / `test_20261011_220545` | **OK** | |
| mg / larc_a / `test_20261011_220737` | FALHOU (rc 139) | defeito nº 4 (corrida), antes da correção |
| mg / larc_a / `test_20261011_221927` | **OK** | |
| matvecsplit / a64fx_s / `test_20261011_222824` | **OK** | |
| xsbench / larc_c / `test_20261011_223237` | INTERROMPIDO | interrompida manualmente aos 12 min, ainda na inicialização |
| matvecsplit / a64fx32 / `test_20261012_111546` | **OK** | primeiro teste do cenário `a64fx32` |
| xsbench / larc_c / `test_20261012_110949` | **OK** | checksum 299541, igual ao nativo |

As execuções que falharam ficam no disco de propósito: são a evidência dos defeitos da seção 2.
`collect_results.py` só lê as que têm `STATUS` começando com `OK`.

### 3.1 O que as execuções OK mostraram

| Workload / cenário | Instruções na ROI | Tempo simulado | IPC agregado | Miss L2 | Simulado == nativo |
|---|---|---|---|---|---|
| mg (classe S) / a64fx_s | 3,33 × 10⁷ | 0,52 ms | 2,40 | 0,38% | sim (`L2 Norm` idêntica) |
| mg (classe S) / larc_a | 2,04 × 10⁸ | 1,04 ms | 2,79 | 0,24% | sim |
| matvecsplit / a64fx_s | 5,16 × 10⁷ | 4,24 ms | 0,46 | 72,17% | sim (`result` idêntico) |
| matvecsplit / a64fx32 | 1,51 × 10⁸ | 4,29 ms | 0,50 | 72,06% | sim |
| xsbench (10⁵ lookups) / larc_c | 1,17 × 10⁸ | 1,95 ms | 0,86 | 0,03% | sim (checksum idêntico) |

Leitura correta desses números:

- **MG classe S não diz nada sobre cache.** A grade é de 32³: cabe até na L2 de 8 MiB, por isso
  o miss rate é quase zero nos dois cenários. Só a classe B (≈ 460 MiB) separa os cenários.
- **MG em 32 núcleos executou 6× mais instruções que em 12** (2,04 × 10⁸ contra 3,33 × 10⁷) para
  o mesmo problema, e o tempo simulado dobrou. Num problema tão pequeno, quase tudo o que as 32
  threads fazem é espera ativa do libgomp. É um artefato do tamanho `test`, mas mostra que IPC e
  potência dinâmica incluem instruções de espera — vale conferir se o efeito some na classe B.
- **XSBench com 10⁵ lookups também não diz nada sobre cache**: 0,03% de miss em 256 MiB é o
  esperado (os 241 MB cabem), mas falta o contraponto em 8 MiB, e 10⁵ lookups tocam pouco da
  tabela. São ~1.170 instruções por lookup, número usado na estimativa da seção 4.
- **A inicialização do XSBench domina o teste**: ela roda numa thread só, fora da ROI, em modo
  de aquecimento de cache, e levou ~26 min. É custo fixo por execução, qualquer que seja o
  número de lookups. Foi por isso que a primeira tentativa pareceu travada e foi interrompida.
- **MatVecSplit** tem entrada única, então este é o único caso em que o `test` já usa a entrada
  do artigo. Mesmo assim é uma execução por cenário, em dois cenários.
- **MatVecSplit não ganha nada com 32 núcleos**, como previsto: o tempo simulado ficou igual
  (4,24 ms → 4,29 ms) e o miss rate também. Os 12 primeiros núcleos ficaram ~100% ocupados e os
  outros 20, ~15% (espera ativa do libgomp antes de dormir), mas cada um desses 20 ainda executou
  ~4,3 × 10⁶ instruções de espera — por isso o total triplicou e a lógica dinâmica do McPAT
  subiu de 30,9 W para 50,3 W sem nenhum trabalho útil a mais.

### 3.2 Potência bruta do McPAT (22 nm, antes de qualquer normalização)

| Workload / cenário | Lógica estática | Lógica dinâmica | L2 estática | L2 dinâmica |
|---|---|---|---|---|
| mg (S) / a64fx_s | 4,46 W | 65,38 W | 0,99 W | 1,12 W |
| mg (S) / larc_a | 12,24 W | 143,22 W | 20,87 W | 4,14 W |
| matvecsplit / a64fx_s | 4,46 W | 30,85 W | 0,99 W | 0,23 W |
| matvecsplit / a64fx32 | 11,95 W | 50,28 W | 0,99 W | 0,23 W |
| xsbench (10⁵) / larc_c | 12,20 W | 74,30 W | 10,80 W | 38,01 W |

A L2 dinâmica de 38 W no XSBench (3,3 × 10⁶ acessos à L2 de 256 MiB em 1,95 ms) é mais um valor
bruto que só faz sentido depois da normalização: o artigo-base assume 9:1 de estática para
dinâmica na cache, e o McPAT aqui dá o inverso.

O que dá para afirmar: a L2 estática cresce com a capacidade (0,99 W em 8 MiB → 20,87 W em
512 MiB) e a lógica dinâmica acompanha a atividade (MatVecSplit, com IPC 0,46, gasta menos da
metade do MG). O que **não** dá para afirmar: qualquer valor absoluto. Em particular, a L1-D
responde por cerca de dois terços da lógica dinâmica (44,6 de 65,4 W no MG / a64fx_s), o que é
suspeito para uma cache de 64 KiB e provavelmente vem de o McPAT 1.0 modelar mal o bloco de
256 bytes. Fica como pendência (seção 5).

---

## 4. Tempo de simulação

Medido nos testes (tempo de parede do `run-sniper`, notebook Ryzen 7 7735HS, 16 threads):

| Execução | Parede | Velocidade em modo detalhado |
|---|---|---|
| mg (S) / a64fx_s | 97 s | 508 mil instr./s |
| mg (S) / larc_a | 506 s | 535 mil instr./s |
| matvecsplit / a64fx_s | 244 s | 360 mil instr./s |
| matvecsplit / a64fx32 | 1.081 s | 206 mil instr./s (rodou junto com outra simulação) |
| xsbench (10⁵) / larc_c | 1.780 s | 558 mil instr./s; ~26 min dos 30 são a fase **anterior** à ROI |

O McPAT leva de 6 a 14 s por execução.

**Estimativa para os tamanhos maiores** (extrapolação, não medição): o trabalho do MG cresce com
pontos da grade × iterações. Da classe S (32³, 4 iterações) para a W (128³, 4 iterações) o fator
é 64; para a B (256³, 20 iterações), 2.560.

| Execução | Instruções estimadas na ROI | Parede estimada a ~0,5 M instr./s |
|---|---|---|
| mg classe W (`mid`), 12 núcleos | ~2 × 10⁹ | ~1 h |
| mg classe B (`full`), 12 núcleos | ~8,5 × 10¹⁰ | ~2 dias |
| xsbench 10⁶ lookups (`mid`) | ~1,2 × 10⁹ | ~40 min + ~26 min de inicialização |
| xsbench 1,5 × 10⁷ lookups (`full`) | ~1,8 × 10¹⁰ | ~10 h + ~26 min de inicialização |
| matvecsplit (qualquer tamanho) | medido | 4 min em 12 núcleos; 18 min em 32 |

Incertezas dessa conta: a velocidade foi medida com conjuntos de trabalho minúsculos e deve cair
quando a simulação passar a ter muitos misses; em 32 núcleos entram as instruções de espera; e a
fase anterior à ROI (aquecimento de cache) também custa tempo e não está na conta.
**Antes de qualquer `full`, rodar um `mid`** para calibrar com um número medido.

Consequência prática: 12 execuções de MG classe B a ~2 dias cada são ~3 a 4 semanas de máquina
ligada, em sequência (cada simulação usa um núcleo do hospedeiro para o Sniper e a memória não
comporta várias em paralelo com folga). Isso precisa ser decidido pela equipe, não por script:
reduzir repetições, reduzir classe, dividir entre máquinas ou assumir o prazo.

---

## 5. Pendências

Em ordem de prioridade.

1. **Completar a matriz de testes** `--size test`: MG e XSBench ainda não rodaram em `a64fx32`.
2. **Rodar `--size mid`** de MG e XSBench em pelo menos um cenário de 12 e um de 32 núcleos, para
   trocar as estimativas da seção 4 por medições.
3. **Decidir o escopo da campanha `full`** com a equipe, à luz da seção 4.
4. **Potência da L1-D no McPAT é implausível.** Em `mg / a64fx_s`, o `power.txt` dá para a L1-D
   de **um** núcleo (64 KiB, 4 vias, bloco de 256 B; `dcache_config = 65536,256,4,2,10,20,0,1`)
   área de 16,1 mm², pico de 13,6 W e 4,6 W dinâmicos. Uma cache desse tamanho a 22 nm deveria
   ocupar uma fração de mm². O `mcpat.py` também repassa `idle_cycles` negativo para alguns
   núcleos (mesma defasagem de relógio da seção 2.4-b). Nada foi alterado: decidir com a equipe
   se a L1 entra na "lógica" como está, se é ajustada ou se a normalização para 27,37 W absorve
   o erro (ela absorve o valor absoluto, mas não a proporção entre L1 e o resto do núcleo).
5. **Combinar com o Membro 1 o formato de entrada** do modelo térmico: quais campos do
   `summary.json` ele lê e se a normalização para 27,37 W usa a potência de pico ou a total.
6. **Corrigir o texto do artigo**: Sniper 8.1 e McPAT 1.0 (não 7.3 e 1.3), AVX2 (não AVX-512),
   GCC 13.3, MatVecSplit denso por blocos (não esparso), modelo térmico desacoplado (não
   "realimentação dinâmica").
7. **Fazer commit** do trabalho. `results/` de teste pode ir junto como evidência do fluxo;
   `benchmarks/third_party/` e `benchmarks/build/` já estão no `.gitignore`.

---

## 6. Limitações que não serão resolvidas

Para declarar em "ameaças à validade", não para consertar:

- x86 com AVX2 em vez de ARM com SVE; GCC 13 em vez do compilador da Fujitsu.
- Simulação por intervalos (Sniper) em vez de ciclo a ciclo (gem5).
- TLB desligada (`translation_enabled = false`): o McPAT não vê atividade de TLB.
- McPAT 1.0, 22 nm, 330 K fixos; LARC é 1,5 nm.
- MatVecSplit usa 12 fatias fixas: em 32 núcleos, 20 threads ficam sem trabalho.
- ROIs de milissegundos, da mesma ordem da constante térmica do modelo (20–100 ms).
- Frequência fixa em 2,2 GHz dentro do Sniper; o *throttling* é aplicado depois, fora dele.
- Simulações multithread não são bit a bit reprodutíveis (o entrelaçamento das threads no
  hospedeiro muda a ordem dos acessos à cache compartilhada); por isso mediana de 3 repetições.
