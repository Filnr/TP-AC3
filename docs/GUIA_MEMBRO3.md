# Guia do Membro 3 — workloads complexos e integração com o McPAT

Este guia explica **o que foi montado, por que foi montado assim e como usar**. Ele foi escrito
para você conseguir apresentar e defender a sua parte. O registro técnico (diagnóstico, testes,
tempos, pendências) está em [`RELATORIO_TECNICO.md`](RELATORIO_TECNICO.md).

> Regra de ouro para a apresentação: tudo o que existe hoje em `results/` com `size=test` é
> **teste de fluxo**. Nenhum número dali é resultado científico. Só execuções `--size full`,
> com 3 repetições e mediana, podem ir para as Tabelas 4, 5 e 6.

---

## A. Visão geral

**Pergunta do trabalho:** quanto do ganho prometido por uma cache L2 gigante empilhada em 3D
(LARC) sobra quando o chip esquenta e precisa reduzir a frequência (*thermal throttling*)?

**Seu papel na cadeia:**

```
Membro 2                 Membro 3 (você)                          Membro 1            Membro 4
configs do Sniper  -->   compila e roda MG, XSBench, MatVecSplit  --> modelo térmico --> tabelas
(4 cenários)             no Sniper; passa as estatísticas pelo        (RC + DVFS,        e gráficos
BabelStream, jacobi      McPAT; entrega summary.json por execução      pós-processo)
```

Você entrega, para cada workload × cenário:

| Dado | Vem de | Quem usa |
|---|---|---|
| tempo simulado, IPC, miss rate da L2 | Sniper | Membro 4 (Tabelas 4 e 6: tempo nominal e speedup teórico) |
| potência estática e dinâmica, separada em lógica e cache L2 | McPAT | Membro 1 (entrada do modelo térmico) |
| taxa de acessos à L2 e fração de tempo com núcleos ocupados | Sniper | Membro 1 (termos "atividade" e "acessos" da Eq. 1) |

O que **não** é seu: temperatura de junção, tempo sob throttling, speedup realista. Isso sai do
script Python do Membro 1, que consome os seus `summary.json`.

---

## B. Os três workloads

### B.1 NPB MG-OMP (classe B)

- **O que resolve:** a equação de Poisson 3D (∇²u = v) numa grade cúbica periódica, pelo método
  *multigrid* (V-cycle). É o benchmark MG do NAS Parallel Benchmarks, versão OpenMP.
- **Intuição:** resolver numa grade fina converge devagar para erros "suaves". O multigrid
  projeta o problema para grades cada vez mais grossas (256³ → 128³ → … → 2³), resolve lá, onde é
  barato, e interpola a correção de volta. Cada nível aplica um *stencil* de 27 pontos.
- **Como acessa a memória:** varreduras regulares sobre vetores 3D enormes. Na classe B são três
  grades de 256³ `double` (≈ 134 MiB cada) mais os níveis grossos: **≈ 460 MiB** no total. O
  acesso é sequencial dentro de cada plano, mas o stencil toca três planos vizinhos e os níveis
  mudam de tamanho o tempo todo — por isso o PDF chama de "multigrid irregular".
- **Por que foi escolhido:** é o workload do artigo-base com a maior queda de miss rate
  (59,8% no A64FX_S → 0,4% no LARC_A) e o maior speedup (pico de 18,57×).
- **Efeito da cache:** 460 MiB não cabem em 8 MiB (A64FX), cabem parcialmente em 256 MiB (LARC_C)
  e cabem inteiros em 512 MiB (LARC_A). É o caso que mais separa LARC_C de LARC_A.
- **Limitações:** a classe B tem só 20 iterações; o tempo simulado é curto (dezenas de ms),
  comparável à constante térmica de 20–100 ms do modelo. Rodamos NPB 3.4.4 (Fortran 90, alocação
  dinâmica); o artigo-base não diz a versão no texto. Em x86/AVX2, não em SVE.

### B.2 XSBench (problema *small*, 15 milhões de lookups)

- **O que resolve:** é um *proxy* do OpenMC. Num transporte de nêutrons por Monte Carlo, ~85% do
  tempo é gasto em uma operação: dado um nêutron com energia E dentro de um material, calcular a
  seção de choque macroscópica. O XSBench faz só isso, milhões de vezes.
- **Intuição:** para cada lookup, sorteia uma energia e um material; faz uma busca binária na
  grade de energia unificada; depois, para cada nuclídeo do material, usa um índice para saltar
  até a tabela daquele nuclídeo e interpola 5 valores.
- **Como acessa a memória:** aleatório e indireto. A busca binária salta pela grade, e cada
  nuclídeo leva a um endereço sem relação com o anterior (*pointer-chasing*: o endereço do
  próximo acesso só é conhecido depois de ler o atual). O *prefetcher* não ajuda.
- **O parâmetro "15M":** são **15 milhões de lookups** (`-l 15000000`), não partículas nem
  isótopos. O artigo-base diz "small problem and 15 million particle lookups". `-s small` =
  68 nuclídeos, 11.303 pontos de grade por nuclídeo, **≈ 241 MB** de dados (medido).
  Usamos `-m event` porque na v20 o modo padrão (`history`) reinterpreta `-l` como "lookups por
  partícula"; o modo `event` mantém o significado antigo (total de lookups), que é o do artigo-base.
- **Por que foi escolhido:** representa acesso irregular, onde largura de banda não resolve —
  só capacidade.
- **Efeito da cache:** 241 MB não cabem em 8 MiB (miss alto), mas cabem em 256 MiB. No artigo-base
  o miss cai de 32,1% para 0,1% já no LARC_C, e o LARC_A não melhora mais: é o caso de
  **saturação da L2** (papel dele na Tabela 3 do PDF).
- **Limitações:** o hash de verificação embutido só existe para a contagem padrão de lookups;
  com `-l 15000000` o programa imprime "INVALID CHECKSUM" e sai com código 1 **por construção**.
  Nossa validação é outra: o checksum da execução simulada tem de ser idêntico ao da execução
  nativa com os mesmos argumentos (e ele não depende do número de threads).

### B.3 MatVecSplit (TAPP kernel 17, ADVENTURE)

- **O que resolve:** um produto matriz-vetor `y = A·x` extraído do solver de elementos finitos
  ADVENTURE (um dos aplicativos prioritários do Fugaku). O RIKEN publicou esses trechos como
  "TAPP kernels", encolhidos para caber em simuladores.
- **Intuição:** a matriz é simétrica e guardada em blocos 6×6 (6 graus de liberdade por nó):
  840 blocos diagonais e 352.380 blocos fora da diagonal (só o triângulo inferior). Para cada
  bloco (i,j) o código faz duas coisas — daí o "split": acumula `A_ij·x_j` na linha i e
  `A_ijᵀ·x_i` na linha j, usando buffers por thread para não haver corrida.
- **Como acessa a memória:** os blocos fora da diagonal ocupam **≈ 101 MB** e são lidos em
  sequência dentro de cada linha de blocos, mas as threads percorrem faixas diferentes e
  intercaladas da matriz, e os vetores são acessados por índice de bloco.
- **Por que foi escolhido:** álgebra linear típica de elementos finitos, com conjunto de trabalho
  entre 8 MiB e 256 MiB — ganho direto de capacidade.
- **Efeito da cache:** 101 MB ≫ 8 MiB. No nosso teste (A64FX_S) o miss rate da L2 foi de ~72%.
- **Limitações (importantes):**
  1. O PDF chama de "esparsa", mas o kernel é um produto **denso por blocos** (triângulo
     inferior completo). Vale corrigir a redação da Tabela 3 ou explicar na apresentação.
  2. O código divide o trabalho em **12 fatias fixas** (`N_THREADS 12`, dimensionado para um
     CMG do A64FX). Com 32 threads, só 12 trabalham; as outras 20 ficam ociosas. Logo, nos
     cenários de 32 núcleos ele **não ganha com os núcleos extras**, só com a cache.
  3. A ROI é uma única multiplicação (a 2ª; a 1ª é aquecimento): poucos milissegundos simulados.
  4. O fonte tem um caminho com intrínsecos SVE (ARM) e um caminho C escalar. Em x86 compila o
     caminho escalar, que o GCC autovetoriza com AVX2.
  5. A correspondência "kernel 17 = `Adventure.region0`" é inferida (ver `benchmarks/VERSIONS.md`).

### OpenMP nos três

Os três usam `#pragma omp parallel for` (ou `!$omp do`): o laço é dividido entre as threads, cada
uma com uma fatia. `OMP_NUM_THREADS` é fixado no número de núcleos do cenário (12 ou 32), como
pede a Seção 3.3 do PDF. Threads sem trabalho ficam em espera ativa por um tempo (*spin-wait* do
libgomp) antes de dormir; essas instruções de espera **são simuladas** e entram no IPC e na
potência dinâmica — efeito visível em problemas minúsculos (MG classe S em 32 núcleos).

---

## C. Compilação e execução

| Arquivo | Função |
|---|---|
| `benchmarks/fetch_workloads.sh` | baixa os três fontes em versões fixas e aplica os patches de ROI |
| `benchmarks/patches/*.patch` | as únicas alterações nos fontes: marcar início/fim da ROI |
| `benchmarks/common/sim_roi_shim.c` | permite chamar `SimRoiStart/End` a partir de Fortran |
| `benchmarks/common/tapp_roi/profiler.h` | transforma `PROF_START/STOP` do kernel TAPP em ROI |
| `benchmarks/Makefile` | alvos `mg`, `xsbench`, `matvecsplit` (os do Membro 2 ficaram intactos) |
| `scripts/build_workloads.sh` | compila dentro do contêiner e confere os binários |
| `scripts/run_workload.sh` | uma execução: nativo → Sniper → validações → McPAT → resumo |
| `scripts/run_mcpat.sh`, `scripts/mcpat_sniper.py` | Sniper → McPAT |
| `scripts/result_summary.py` | gera `summary.json` com a origem de cada número |
| `scripts/run_campaign.sh`, `scripts/collect_results.py` | campanha e mediana |
| `configs/power.cfg` | nó tecnológico informado ao McPAT |

**Flags e o porquê:**

- `-O3`: nível de otimização do artigo.
- `-mavx2 -mfma` no lugar de `-mavx512f -mavx512cd`: o Sniper executa o binário de verdade na
  sua CPU (via Intel SDE) e observa as instruções. O Ryzen 7 7735HS não tem AVX-512, então um
  binário AVX-512 morreria com *illegal instruction*. É a mesma decisão já registrada pela equipe
  no `benchmarks/Makefile`. Consequência: vetores de 256 bits em vez de 512.
- `-fopenmp`: liga o OpenMP.
- **sem** `-ffast-math`: manteria os testes de verificação numérica dos benchmarks inválidos.
- `-DSNIPER_ROI` (XSBench): ativa os marcadores do patch.
- `-flto -std=gnu99 -DOPENMP` (XSBench): são as flags do Makefile oficial.

**Por que compilar dentro do contêiner:** garante o mesmo GCC, gfortran e glibc para os cinco
integrantes, e é o mesmo ambiente em que o Sniper roda.

**Parâmetros de execução (`--size`):**

| `--size` | MG | XSBench | MatVecSplit | Uso |
|---|---|---|---|---|
| `test` | classe S (32³, 4 it.) | 100 mil lookups | entrada única | validar o fluxo (minutos) |
| `mid` | classe W (128³, 4 it.) | 1 milhão de lookups | entrada única | calibrar tempo (dezenas de min a horas) |
| `full` | **classe B** (256³, 20 it.) | **15 milhões** de lookups | entrada única | experimento do artigo |

---

## D. Sniper

- **O que é:** um simulador de *timing* de processadores multicore. Ele não interpreta o
  programa: o binário roda nativamente sob o Intel SDE, que registra o fluxo de instruções e
  endereços (traço SIFT). O Sniper recebe esse fluxo e calcula **quanto tempo** aquilo levaria
  na arquitetura configurada.
- **Simulação por intervalos:** em vez de simular cada estágio do pipeline a cada ciclo (como o
  gem5 do artigo-base), o modelo *interval* assume que o núcleo despacha instruções a uma taxa
  constante entre "eventos de perda" (cache miss, erro de predição de desvio) e calcula a
  penalidade de cada evento. É de 10 a 100× mais rápido que ciclo a ciclo, com erro típico de
  dezenas de por cento em valores absolutos, mas boa fidelidade em **tendências relativas**.
- **Os cenários:** `configs/larc_base.cfg` define o que é comum (núcleo OoO de 128 entradas de
  ROB e largura 4, L1 de 64 KiB, bloco de 256 B, L2 de 16 vias e 37 ciclos, 2,2 GHz). Cada
  cenário muda três coisas: número de núcleos, tamanho da L2 e banda L1↔L2.

  | Cenário | Núcleos | L2 | Para que serve |
  |---|---|---|---|
  | A64FX_S | 12 | 8 MiB | linha de base (um CMG do A64FX real) |
  | A64FX32 | 32 | 8 MiB | isola o efeito de "mais núcleos" (contenção na mesma cache) |
  | LARC_C | 32 | 256 MiB | isola o efeito de "mais cache" |
  | LARC_A | 32 | 512 MiB | mais cache e mais banda |

- **O que é representado e o que é aproximação:** "32 núcleos" no Sniper significa 32 modelos de
  núcleo idênticos compartilhando uma L2 e um barramento. **Não** representa: a ISA ARM/SVE (roda
  x86), o preditor *bi-mode* (usa-se `pentium_m`), o *prefetcher* de linha adjacente exato, TLB
  (tradução de endereços desligada), o empilhamento 3D em si (a cache gigante é só "uma L2 com
  mais conjuntos e a mesma latência"), nem a topologia física. É um modelo funcional de desempenho,
  não uma validação de hardware.
- **ROI (região de interesse):** `SimRoiStart()`/`SimRoiEnd()` são instruções mágicas que o
  simulador reconhece. Antes da ROI o Sniper só aquece as caches (*cache-only*); dentro dela
  simula em detalhe; depois avança rápido. Todas as estatísticas que usamos são da ROI.
- **Estatísticas:** ficam em `sniper/simulation/sim.stats.sqlite3` (banco com centenas de
  contadores por núcleo), `sim.out` (resumo legível) e `sim.cfg` (configuração efetiva).
- **Simulado × nativo:** o MG classe B leva ~2 s para rodar de verdade no seu notebook e levará
  horas para ser *simulado*. E o "tempo" que interessa não é nenhum desses dois: é o **tempo
  simulado** (`simulated_time_s`), isto é, quanto o programa levaria no processador modelado.
  Tempo de parede da simulação só serve para planejar a campanha.

**Três defeitos do Sniper 8.1 que tivemos de corrigir** (patches no `docker/Dockerfile`, cada um
com a explicação): variável não inicializada que abortava qualquer cenário com cache
compartilhada; uma thread "fantasma" criada a cada programa multithread (tratamento de `clone3`);
e uma condição de corrida que derrubava simulações de 32 threads. Sem eles nenhum dos quatro
cenários executava.

---

## E. McPAT

- **O que é:** um modelo analítico de potência, área e *timing*. Recebe uma descrição do chip
  (quantos núcleos, tamanho das caches, nó tecnológico, tensão) e contadores de atividade
  (instruções, acessos e misses de cache, desvios) e devolve potência por componente.
- **Como os dados chegam:** o McPAT não lê a saída do Sniper. Ele quer um XML próprio. Quem faz a
  ponte é o `tools/mcpat.py` do Sniper: lê `sim.cfg` + `sim.stats.sqlite3`, preenche um modelo de
  XML (`power.xml`), chama o binário e interpreta a saída (`power.txt`).
- **O adaptador que foi necessário:** o `mcpat.py` desta versão procura contadores com nomes
  antigos (`L1-D.loads`, `itlb.miss`…), que o Sniper 8.1 passou a gravar como `L1-D.tloads`,
  `mmu.tlb_misses_instruction` etc. Ele abortava com `KeyError`. `scripts/mcpat_sniper.py` cria
  os apelidos e reaproveita todo o resto do `mcpat.py` original.
- **Dinâmica × estática:**
  - *Dinâmica* = energia gasta chaveando transistores (C·V²·f·atividade). Depende do que o
    programa faz. No McPAT: "Runtime Dynamic".
  - *Estática* = corrente de fuga, gasta mesmo parado. Depende de área, nó, tensão e
    **temperatura**. No McPAT: "Subthreshold Leakage (with power gating)" + "Gate Leakage".
- **O que influencia a estimativa:** nó tecnológico (22 nm, o menor que o McPAT 1.0 tem),
  tamanho/associatividade/bloco de cada cache, número de núcleos, frequência, e os contadores.
- **Como interpretar:** os watts absolutos **não são os do LARC**. O McPAT modela um x86 genérico
  a 22 nm e 330 K; o LARC é ARM a 1,5 nm. Por isso a Seção 4.1 do PDF normaliza para o orçamento
  do artigo-base. O que o McPAT fornece de útil é a **proporção**: quanto da potência é dinâmica,
  como ela varia entre workloads e cenários.

**O orçamento de referência (cuidado com as unidades):**

| Valor | Refere-se a | Observação |
|---|---|---|
| 27,37 W | lógica de **1 CMG** (32 núcleos + interface de memória) a 1,5 nm | A64FX: 122 W de pico → 1,98 W/núcleo → escalado por nó |
| 6,14 W | potência **estática** da L2 de **384 MiB** de 1 CMG | 64 mW por 4 MiB × 96 |
| 9:1 | estática:dinâmica na cache, a 350 K | logo a cache total de 1 CMG = 6,14 / 0,9 = 6,83 W |
| 547 W | chip inteiro = **16 CMGs** | 16 × 27,37 (438 W) + 16 × 6,83 (109 W) |

Erros a evitar: comparar 547 W (chip) com a potência de um cenário (um CMG); somar os 6,14 W à
potência de cache que o McPAT já calculou; usar 6,14 W para 256 ou 512 MiB sem dizer que ele é de
384 MiB. O `summary.json` traz, no bloco `derived`, o valor reescalado para a capacidade simulada
(16 mW/MiB → 4,10 W para 256 MiB; 8,19 W para 512 MiB), rotulado como calculado.

---

## F. Fluxo completo dos dados

```
fetch_workloads.sh ──> fontes + patches de ROI
build_workloads.sh ──> benchmarks/bin-m3/{mg.B.x, XSBench, matvecsplit}
run_workload.sh W C --size full --rep N
   ├─ execução nativa ........................ native.log   (referência do resultado numérico)
   ├─ run-sniper -n <núcleos> -c C -c power .. sniper.log, sniper/simulation/{sim.out,sim.cfg,sim.stats.sqlite3}
   ├─ validações: código de saída, ROI fechada, verificação do benchmark, simulado == nativo
   ├─ mcpat_sniper.py ........................ mcpat/{power.xml, power.txt, mcpat_power.json}
   └─ result_summary.py ...................... summary.json  +  STATUS
collect_results.py --size full ──> results/summary_full.csv (mediana de 3 repetições)
                                      ├─> Membro 4: Tabela 4 (miss L2), Tabela 6 (tempo nominal, speedup teórico)
                                      └─> Membro 1: potência e atividade → T_j, throttling → Tabelas 5 e 6 (realista)
```

Cada `summary.json` tem quatro blocos, para não misturar origens:
`sniper` (simulado), `mcpat` (estimado), `paper_reference` (constantes do artigo) e `derived` (contas).

---

## G. Interpretação dos resultados

**Como cada workload ajuda a responder a pergunta de pesquisa:**

- **MG** é o caso em que a cache 3D mais ajuda. Se o throttling corroer o ganho aqui, a hipótese
  ganha força; é também o teste da diferença LARC_C × LARC_A.
- **XSBench** mostra o ganho saturando em 256 MiB. Como é irregular, os núcleos passam mais tempo
  esperando memória → menor atividade → menos potência dinâmica. Espera-se que aqueça menos que
  cargas contínuas (é a comparação "sustentadas vs. esparsas" da Seção 5.2).
- **MatVecSplit** é o controle de "ganho só de cache": como usa 12 threads, o que mudar entre
  A64FX32 e LARC vem da capacidade, não dos núcleos.

**O que já dá para concluir (com os testes curtos):**

- o fluxo Sniper → McPAT funciona de ponta a ponta nos cenários de 12 e de 32 núcleos, inclusive
  com L2 de 512 MiB;
- os três binários produzem, sob simulação, exatamente o mesmo resultado numérico da execução nativa;
- o MatVecSplit, que tem entrada única, mostrou miss rate de L2 alto (~72%) com 8 MiB, coerente
  em direção com o artigo-base (46,7%) — **uma execução, sem repetição, não é dado de tabela**.

**O que só dá para concluir depois da campanha:**

- qualquer miss rate, IPC, tempo, speedup ou potência de MG classe B e XSBench 15M;
- se a ordenação relativa bate com a Tabela 3 do artigo-base;
- qualquer afirmação sobre temperatura, throttling ou degradação de speedup (depende também do
  modelo do Membro 1).

**Uma ressalva de modelagem que vale levar à equipe:** o fluxo atual simula a 2,2 GHz fixos e
aplica o modelo térmico *depois* (pós-processamento, Eqs. 5–7). A frequência **não** é reduzida
dinamicamente dentro do Sniper. O PDF fala em "realimentação dinâmica"; o que existe é um modelo
desacoplado. Dizer "o Sniper reduziu a frequência" seria incorreto.

---

## H. Perguntas prováveis na apresentação

**1. Por que MG classe B e não uma classe maior?**
É a classe do artigo-base (todas as NPB-OMP em classe B). Ela tem ~460 MiB de dados: não cabe em
8 MiB, cabe em parte em 256 MiB e cabe inteira em 512 MiB — exatamente a faixa que separa os
quatro cenários. Classes maiores inviabilizariam a simulação.

**2. Por que o MG tem miss rate tão alto no A64FX e quase zero no LARC_A?**
Cada varredura percorre grades de centenas de MiB. Com 8 MiB, quase todo bloco novo foi expulso
desde o último uso. Com 512 MiB o conjunto de trabalho inteiro fica residente e só o primeiro
toque falha.

**3. O que são os "15 milhões" do XSBench?**
Número total de lookups de seção de choque (`-l 15000000`), no problema `small` (68 nuclídeos).
Conferimos no código: no modo `event` da v20, `-l` é o total de lookups, como nas versões antigas
usadas pelo artigo-base. Não são partículas, isótopos nem bytes.

**4. Por que o XSBench imprime "INVALID CHECKSUM" e mesmo assim vocês aceitam?**
O hash de referência embutido só vale para a quantidade padrão de lookups (com ela, obtivemos
"Valid"). Para 15 milhões validamos de outra forma: o checksum sob simulação tem de ser idêntico
ao da execução nativa, e ele é determinístico e independente do número de threads.

**5. O que é pointer-chasing e por que a cache grande ajuda mais que banda?**
É quando o endereço do próximo acesso depende do dado lido no acesso atual. Não há como buscar
adiantado nem em paralelo, então cada miss custa a latência cheia. Mais banda não ajuda; ter o
dado já na cache, sim.

**6. O MatVecSplit é esparso?**
Não exatamente. É um produto matriz-vetor de elementos finitos armazenado em blocos 6×6, com o
triângulo inferior completo. É "MatVec" do ADVENTURE; "split" porque cada bloco contribui para
duas linhas. O texto do nosso artigo o chama de esparso e isso deve ser ajustado.

**7. Por que o MatVecSplit não escala de 12 para 32 núcleos?**
O kernel foi escrito para um CMG de 12 núcleos e divide o trabalho em 12 fatias fixas. Com 32
threads, 20 ficam sem trabalho. Mantivemos o código oficial sem alterar; é uma limitação declarada.

**8. O que o OpenMP faz aqui e por que fixar `OMP_NUM_THREADS`?**
Divide os laços entre threads. Fixamos no número de núcleos do cenário para a execução ser
reprodutível e para cada thread ter um núcleo simulado próprio.

**9. Por que a L2 é a última cache? Não há L3?**
No A64FX (e no LARC) a L2 é o último nível, compartilhada pelos núcleos de um CMG. O empilhamento
3D aumenta justamente essa L2.

**10. Como o miss rate é calculado?**
(misses de leitura + misses de escrita) ÷ (leituras + escritas) que chegaram à L2, dentro da ROI,
somando os núcleos. Só chegam à L2 os acessos que falharam na L1.

**11. Por que Sniper e não gem5, como no artigo-base?**
O gem5 é ciclo a ciclo e levou meses por workload. O Sniper usa simulação por intervalos: mais
rápido, com perda de precisão absoluta. Aceitamos isso porque nos interessam tendências entre
cenários. Mesmo assim, a campanha completa leva dias num notebook.

**12. Vocês usaram Sniper 7.3 e McPAT 1.3 como diz o texto?**
Não. O ambiente real é Sniper 8.1 (commit fixado) com três correções nossas, e o McPAT 1.0 que
vem com ele. O texto precisa ser corrigido. Também usamos AVX2 em vez de AVX-512, porque a CPU
hospedeira não tem AVX-512.

**13. O McPAT mede potência?**
Não. Estima, por modelo analítico, a partir da configuração e dos contadores de atividade. Além
disso modela x86 a 22 nm, não ARM a 1,5 nm. Por isso normalizamos para o orçamento do artigo-base
e usamos o McPAT pela proporção, não pelo valor absoluto.

**14. Qual a diferença entre potência dinâmica e estática, e por que isso importa em cache 3D?**
Dinâmica vem do chaveamento e depende da atividade; estática é fuga e existe mesmo parado,
crescendo com a temperatura. Uma SRAM enorme é dominada por fuga (9:1 no artigo-base). Isso cria
uma realimentação: mais calor → mais fuga → mais calor.

**15. Os 547 W são a potência do que vocês simularam?**
Não. É o TDP do chip completo de 16 CMGs. Simulamos um CMG: teto de 27,37 W de lógica mais a
cache (6,83 W para 384 MiB).

**16. Como garantem reprodutibilidade?**
Imagem Docker com commit do Sniper fixo; fontes dos benchmarks em versões fixas com SHA/commit;
cada execução grava o comando exato, o ID da imagem, o commit do repositório e os códigos de saída;
resultados nunca são sobrescritos; três repetições com mediana.

**17. Se a simulação é determinística, por que três repetições?**
Não é totalmente determinística: com várias threads, o entrelaçamento real das threads no
hospedeiro muda a ordem dos acessos à cache compartilhada. Vimos a contagem de instruções da mesma
entrada variar alguns por cento entre duas execuções.

**18. Como validaram que o programa simulado está correto?**
Quatro verificações obrigatórias por execução: código de saída; ROI aberta e fechada; verificação
numérica do próprio benchmark; e resultado idêntico ao da execução nativa. Se qualquer uma falha,
a execução é marcada `FALHOU` e não entra na consolidação.

**19. Qual a diferença entre o que já rodaram e o resultado científico?**
Rodamos entradas reduzidas, uma vez, em parte dos cenários, para provar que o fluxo funciona.
Resultado científico exige a entrada do artigo, os quatro cenários, três repetições e mediana.
Os scripts marcam cada execução com o tamanho usado e a consolidação separa as duas coisas.

**20. Quais são as principais ameaças à validade da sua parte?**
ISA x86/AVX2 em vez de ARM/SVE; simulação por intervalos em vez de ciclo a ciclo; McPAT 1.0 a
22 nm; TLB não modelada; MatVecSplit limitado a 12 threads; ROIs curtas (ms) frente à constante
térmica; e o modelo térmico desacoplado da simulação.

---

## I. Guia rápido de execução

Todos os comandos a partir da raiz do repositório.

```bash
# 1. Verificar o ambiente (não simula nada)
./scripts/check_env.sh

# (só na primeira vez ou depois de mudar o Dockerfile)
./scripts/build_image.sh

# 2. Baixar os fontes e compilar os três workloads
./benchmarks/fetch_workloads.sh
./scripts/build_workloads.sh                 # ou: ./scripts/build_workloads.sh mg|xsbench|matvecsplit

# 3. Testes rápidos (minutos cada; --dry-run mostra o comando sem executar)
./scripts/run_workload.sh mg          a64fx_s --size test
./scripts/run_workload.sh matvecsplit a64fx_s --size test
./scripts/run_workload.sh xsbench     larc_c  --size test

# 4. Validar a integração com o McPAT (já roda ao final do passo 3; isolado:)
./scripts/run_mcpat.sh results/mg/a64fx_s/<execucao>

# 5. Experimentos completos, um por vez (horas a dias cada — ver RELATORIO_TECNICO.md)
./scripts/run_workload.sh mg          a64fx_s --size full --rep 1
./scripts/run_workload.sh xsbench     larc_c  --size full --rep 1
./scripts/run_workload.sh matvecsplit larc_a  --size full --rep 1
#    cenários: a64fx_s  a64fx32  larc_c  larc_a      repetições: --rep 1, 2, 3

#    ou a campanha inteira (sem --confirm só lista o que faria; retoma de onde parou)
./scripts/run_campaign.sh
./scripts/run_campaign.sh --confirm
./scripts/run_campaign.sh --workloads "matvecsplit" --scenarios "a64fx_s larc_c" --reps 3 --confirm

# 6. Resultados
./scripts/collect_results.py --size full      # mediana -> results/summary_full.csv
```

**Onde estão as coisas:**

| O quê | Onde |
|---|---|
| uma execução | `results/<workload>/<cenario>/<size>_<data>_rep<N>/` |
| deu certo? | `STATUS` (`OK`, `FALHOU: motivo`, `PARCIAL`, `INTERROMPIDO`) |
| comando exato e ambiente | `command.txt` |
| saída do benchmark | `native.log` (nativo) e `sniper.log` (simulado) |
| estatísticas do Sniper | `sniper/simulation/sim.out`, `sim.cfg`, `sim.stats.sqlite3` |
| McPAT | `mcpat/power.xml` (entrada), `mcpat/power.txt` (saída bruta), `mcpat/mcpat.log` |
| resumo para a equipe | `summary.json` |
| logs de build e campanha | `results/_logs/` |
