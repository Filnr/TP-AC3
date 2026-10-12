# Versões e dependências — workloads do Membro 3

Verificado em 2026-10-11 na imagem `larc-thermal-sniper:latest` (ver `./scripts/check_env.sh`).

## Ferramentas (reais × citadas no artigo)

| Componente | Citado no PDF (Seção 3.3) | Efetivamente usado | Observação |
|---|---|---|---|
| Sniper | 7.3 | **8.1**, commit `56505e4` + 3 patches locais (`docker/Dockerfile`) | frontend SDE/SIFT (trace-driven) |
| McPAT | 1.3 | **1.0** (binário `mcpat-1.0.cache` distribuído com o Sniper, de 2013) | nós de 90–22 nm; 330 K fixo no template |
| SO | Ubuntu 22.04, kernel 5.15 | Ubuntu 24.04 (contêiner) sobre Arch Linux, kernel 7.2 | `intel_pstate=disable` não se aplica (host AMD) |
| Compilador | GCC 11.4 | GCC / gfortran **13.3.0** | |
| Flags | `-O3 -mavx512f -mavx512cd -fopenmp` | `-O3 -mavx2 -mfma -fopenmp` | host (Ryzen 7 7735HS) não tem AVX-512; mesma escolha do `benchmarks/Makefile` da equipe |
| Python | — | 3.12.3 (contêiner) | scripts do Sniper e do McPAT |

## Fontes dos workloads (`benchmarks/fetch_workloads.sh`)

| Workload | Origem | Versão fixada | Modificação |
|---|---|---|---|
| NPB MG-OMP | https://www.nas.nasa.gov/assets/npb/NPB3.4.4.tar.gz | NPB **3.4.4** (`NPB3.4-OMP/MG`), SHA-256 `1ae21939…523549` | `patches/npb-mg-roi.patch`: 2 chamadas (`sim_roi_start/end`) em volta da região `T_bench` |
| XSBench | https://github.com/ANL-CESAR/XSBench | **v20** + 24 commits, `ba08e52` (2024-03-11), `openmp-threading/` | `patches/xsbench-roi.patch`: `SimRoiStart/End` em volta da simulação, sob `-DSNIPER_ROI` |
| MatVecSplit | https://github.com/RIKEN-RCCS/fs2020-tapp-kernels | `112d97e` (2022-11-22), `Adventure.region0.20170821` | nenhuma no fonte; ROI entra por `common/tapp_roi/profiler.h` (`PROF_START/STOP`) |

### Sobre a identificação do "kernel 17"

O artigo-base chama o kernel 17 de "ADVENTURE's MatVecSplit". O repositório do RIKEN não usa esse
nome nem numera os diretórios. A correspondência adotada é **inferida**, com estas evidências:
o README do repositório numera `Adventure CoarseMatVec (region1)` como kernel **18** (o artigo-base
chama o 18 de "MatVecDotP", limitado a 12 threads — e `region1` de fato tem `MAX_NUM_THREADS`
e é um produto interno); `region0` é o diretório imediatamente anterior e o único kernel do
ADVENTURE que implementa um produto matriz-vetor (`MatVec_product`), separado ("split") em parte
triangular inferior, superior transposta e bloco diagonal. Portanto: kernel 17 = `Adventure.region0`.
