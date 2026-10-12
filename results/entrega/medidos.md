# Valores MEDIDOS (Sniper 8.1 + McPAT 1.0)

Uma linha por workload x cenario x tamanho. Potencia = saida bruta do McPAT (x86, 22 nm), antes da normalizacao da Secao 4.1. So as linhas com escala_do_artigo = sim usam a entrada do artigo.

| workload | cenario | tamanho | entrada | n | escala_do_artigo | instrucoes_roi | tempo_simulado_s | ipc_agregado | l2_miss_pct | speedup_vs_a64fx_s | nucleos_ocupados_frac | logica_estatica_W | logica_dinamica_W | l2_estatica_W | l2_dinamica_W | parede_s | l2_miss_pct_artigo_base |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mg | a64fx_s | test | classe S (32^3, 4 it.) | 1 | nao | 3.330e+07 | 0.000525 | 2.403 | 0.38 | 1.00 | 0.93 | 4.46 | 65.38 | 0.99 | 1.12 | 97 | n/d |
| mg | larc_a | test | classe S (32^3, 4 it.) | 1 | nao | 2.035e+08 | 0.001035 | 2.792 | 0.24 | 0.51 | 0.91 | 12.24 | 143.22 | 20.87 | 4.14 | 506 | n/d |
| xsbench | a64fx_s | test | small, 1e5 lookups | 1 | nao | 1.134e+08 | 0.009896 | 0.434 | 58.79 | 1.00 | 1.00 | 4.46 | 15.90 | 0.99 | 0.84 | 1412 | n/d |
| xsbench | a64fx32 | test | small, 1e5 lookups | 1 | nao | 1.203e+08 | 0.005135 | 0.333 | 72.74 | 1.93 | 0.99 | 11.95 | 35.56 | 0.99 | 3.82 | 1573 | n/d |
| xsbench | larc_c | test | small, 1e5 lookups | 1 | nao | 1.173e+08 | 0.001946 | 0.856 | 0.03 | 5.09 | 0.98 | 12.20 | 74.30 | 10.80 | 38.01 | 1780 | n/d |
| xsbench | larc_a | test | small, 1e5 lookups | 1 | nao | 1.163e+08 | 0.001576 | 1.048 | 0.02 | 6.28 | 0.97 | 12.24 | 89.33 | 20.87 | 62.03 | 3465 | n/d |
| matvecsplit | a64fx_s | test | TAPP kernel 17 (entrada unica, a do artigo) | 1 | sim | 5.156e+07 | 0.004236 | 0.461 | 72.17 | 1.00 | 1.00 | 4.46 | 30.85 | 0.99 | 0.23 | 244 | 46.7 |
| matvecsplit | a64fx32 | test | TAPP kernel 17 (entrada unica, a do artigo) | 1 | sim | 1.510e+08 | 0.004287 | 0.500 | 72.06 | 0.99 | 0.46 | 11.95 | 50.28 | 0.99 | 0.23 | 1081 | n/d |
| matvecsplit | larc_c | test | TAPP kernel 17 (entrada unica, a do artigo) | 1 | sim | 1.235e+08 | 0.001426 | 1.231 | 0.01 | 2.97 | 0.59 | 12.20 | 121.96 | 10.80 | 8.75 | 434 | n/d |
| matvecsplit | larc_a | test | TAPP kernel 17 (entrada unica, a do artigo) | 1 | sim | 1.181e+08 | 0.001276 | 1.315 | 0.02 | 3.32 | 0.59 | 12.24 | 132.65 | 20.87 | 12.90 | 433 | n/d |
