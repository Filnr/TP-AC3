# PROJECAO para a entrada do artigo (NAO e resultado de simulacao)

Cada linha = valor medido no tamanho `base_medida` x `fator`. Regras no cabecalho de `scripts/project_results.py`. `erro_regra_*` = quanto a mesma regra errou ao prever o tamanho mid a partir do test (positivo = superestimou). MatVecSplit nao aparece: ja foi medido com a entrada do artigo (ver medidos.md).

| workload | cenario | origem | entrada_projetada | base_medida | fator | instrucoes_roi | tempo_simulado_s | speedup_vs_a64fx_s | ipc_agregado | l2_miss_pct | l2_miss_pct_medido_na_base | l2_miss_pct_artigo_base | logica_estatica_W | logica_dinamica_W | l2_estatica_W | l2_dinamica_W | energia_J | parede_estimada_h | erro_regra_instr_pct | erro_regra_tempo_pct | confianca |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mg | a64fx_s | PROJETADO | classe B (256^3, 20 it.) | classe S (32^3, 4 it.) | 2560 | 8.526e+10 | 1.3439 | 1.00 | 2.403 | nao projetado | 0.38 | 59.8 | 4.46 | 65.38 | 0.99 | 1.12 | 96.697 | 46.6 | n/d | n/d | baixa (um ponto medido so: test) |
| mg | larc_a | PROJETADO | classe B (256^3, 20 it.) | classe S (32^3, 4 it.) | 2560 | 5.210e+11 | 2.6505 | 0.51 | 2.792 | nao projetado | 0.24 | 0.4 | 12.24 | 143.22 | 20.87 | 4.14 | 478.322 | 270.4 | n/d | n/d | baixa (um ponto medido so: test) |
| xsbench | a64fx_s | PROJETADO | small, 1,5e7 lookups | small, 1e5 lookups | 150 | 1.702e+10 | 1.4844 | 1.00 | 0.434 | 58.79 | 58.79 | 32.1 | 4.46 | 15.90 | 0.99 | 0.84 | 32.951 | 11.2 | n/d | n/d | baixa (um ponto medido so: test) |
| xsbench | a64fx32 | PROJETADO | small, 1,5e7 lookups | small, 1e5 lookups | 150 | 1.805e+10 | 0.7702 | 1.93 | 0.333 | 72.74 | 72.74 | n/d | 11.95 | 35.56 | 0.99 | 3.82 | 40.296 | 16.4 | n/d | n/d | baixa (um ponto medido so: test) |
| xsbench | larc_c | PROJETADO | small, 1,5e7 lookups | small, 1e5 lookups | 150 | 1.760e+10 | 0.2919 | 5.09 | 0.856 | 0.03 | 0.03 | 0.1 | 12.20 | 74.30 | 10.80 | 38.01 | 39.498 | 9.2 | n/d | n/d | baixa (um ponto medido so: test) |
| xsbench | larc_a | PROJETADO | small, 1,5e7 lookups | small, 1e5 lookups | 150 | 1.744e+10 | 0.2364 | 6.28 | 1.048 | 0.02 | 0.02 | n/d | 12.24 | 89.33 | 20.87 | 62.03 | 43.604 | 11.9 | n/d | n/d | baixa (um ponto medido so: test) |
