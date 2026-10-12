#!/usr/bin/env python3
"""Tabelas de entrega do Membro 3: o que foi MEDIDO em escala reduzida e a PROJECAO para a
escala do artigo. Roda no host (so biblioteca padrao; graficos se houver matplotlib).

Uso: ./scripts/project_results.py            -> results/entrega/{medidos,projecao}.{csv,md}

Medido   = saida do Sniper/McPAT em execucoes com STATUS "OK" (mediana se houver repeticoes).
Projetado = medido no maior tamanho disponivel x fator de trabalho ate a entrada do artigo:
  instrucoes e tempo simulado  x fator   (MG: pontos da grade x iteracoes; XSBench: lookups)
  potencia (W)                 mantida   (e taxa); energia = potencia x tempo projetado
  miss L2                      XSBench: mantido (regime estacionario); MG: NAO projetado
  speedup                      razao dos tempos projetados
A regra e conferida prevendo o tamanho 'mid' a partir do 'test' e comparando com o medido.
Nenhuma linha projetada e resultado de simulacao; a coluna 'origem' diz o que e cada uma.
"""
import csv
import glob
import json
import os
import re
import statistics

from collect_results import ROOT, SCENARIOS, WORKLOADS, get

OUT = os.path.join(ROOT, 'results', 'entrega')
SIZES = ['test', 'mid', 'full']
# trabalho por tamanho: MG = pontos x iteracoes (classes S, W, B); XSBench = lookups
WORK = {
    'mg': {'test': 32 ** 3 * 4, 'mid': 128 ** 3 * 4, 'full': 256 ** 3 * 20},
    'xsbench': {'test': 1e5, 'mid': 1e6, 'full': 1.5e7},
}
INPUT = {
    'mg': {'test': 'classe S (32^3, 4 it.)', 'mid': 'classe W (128^3, 4 it.)', 'full': 'classe B (256^3, 20 it.)'},
    'xsbench': {'test': 'small, 1e5 lookups', 'mid': 'small, 1e6 lookups', 'full': 'small, 1,5e7 lookups'},
    'matvecsplit': dict.fromkeys(SIZES, 'TAPP kernel 17 (entrada unica, a do artigo)'),
}
# Miss rate da L2 no artigo-base (Domke et al. 2023), valores citados em docs/GUIA_MEMBRO3.md.
PAPER_MISS = {('mg', 'a64fx_s'): 59.8, ('mg', 'larc_a'): 0.4, ('xsbench', 'a64fx_s'): 32.1,
              ('xsbench', 'larc_c'): 0.1, ('matvecsplit', 'a64fx_s'): 46.7}
FIELDS = [  # coluna, caminho no summary.json
    ('instrucoes_roi', 'sniper.instructions_total'),
    ('tempo_simulado_s', 'sniper.simulated_time_s'),
    ('ipc_agregado', 'sniper.ipc_aggregate'),
    ('l2_miss_pct', 'sniper.l2.miss_rate_pct'),
    ('l2_acessos', 'sniper.l2.accesses'),
    ('nucleos_ocupados_frac', 'sniper.core_busy_fraction_avg'),
    ('logica_estatica_W', 'mcpat.static.logic_W'),
    ('logica_dinamica_W', 'mcpat.dynamic.logic_W'),
    ('l2_estatica_W', 'mcpat.static.l2_cache_W'),
    ('l2_dinamica_W', 'mcpat.dynamic.l2_cache_W'),
    ('parede_s', 'run.sniper_wall_s'),
]


def load():
    """(workload, cenario, size) -> dict com a mediana de cada campo, n e velocidade detalhada."""
    data = {}
    for w in WORKLOADS:
        for s in SCENARIOS:
            for size in SIZES:
                runs, kips = [], []
                for d in sorted(glob.glob(os.path.join(ROOT, 'results', w, s, size + '_*'))):
                    st, sj = os.path.join(d, 'STATUS'), os.path.join(d, 'summary.json')
                    if not (os.path.isfile(st) and open(st).read().startswith('OK') and os.path.isfile(sj)):
                        continue
                    runs.append(json.load(open(sj)))
                    m = re.search(r'Simulation speed ([\d.]+) KIPS', open(os.path.join(d, 'sniper.log'), errors='replace').read())
                    if m:
                        kips.append(float(m.group(1)))
                if not runs:
                    continue
                row = {'n': len(runs)}
                for col, path in FIELDS:
                    vals = [float(v) for v in (get(r, path) for r in runs) if v is not None]
                    row[col] = statistics.median(vals) if vals else None
                row['kips'] = statistics.median(kips) if kips else None
                data[(w, s, size)] = row
    return data


def fmt(v, p='%.3g'):
    return 'n/d' if v is None else (v if isinstance(v, str) else p % v)


def write(name, cols, rows, header):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + '.csv'), 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=[c for c, _ in cols])
        wr.writeheader()
        wr.writerows([{c: r.get(c) for c, _ in cols} for r in rows])
    with open(os.path.join(OUT, name + '.md'), 'w') as f:
        f.write(header + '\n\n| ' + ' | '.join(c for c, _ in cols) + ' |\n|' + '---|' * len(cols) + '\n')
        for r in rows:
            f.write('| ' + ' | '.join(fmt(r.get(c), p) for c, p in cols) + ' |\n')


def main():
    data = load()
    if not data:
        raise SystemExit('Nenhuma execucao OK em results/.')

    # ---- medidos
    med = []
    for (w, s, size), r in data.items():
        base = data.get((w, 'a64fx_s', size))
        row = dict(r, workload=w, cenario=s, tamanho=size, entrada=INPUT[w][size], origem='medido',
                   escala_do_artigo='sim' if (size == 'full' or w == 'matvecsplit') else 'nao')
        row['speedup_vs_a64fx_s'] = base['tempo_simulado_s'] / r['tempo_simulado_s'] if base else None
        row['l2_miss_pct_artigo_base'] = PAPER_MISS.get((w, s)) if row['escala_do_artigo'] == 'sim' else None
        med.append(row)
    med.sort(key=lambda r: (WORKLOADS.index(r['workload']), SIZES.index(r['tamanho']), SCENARIOS.index(r['cenario'])))
    mcols = [('workload', '%s'), ('cenario', '%s'), ('tamanho', '%s'), ('entrada', '%s'), ('n', '%d'),
             ('escala_do_artigo', '%s'), ('instrucoes_roi', '%.3e'), ('tempo_simulado_s', '%.6f'),
             ('ipc_agregado', '%.3f'), ('l2_miss_pct', '%.2f'), ('speedup_vs_a64fx_s', '%.2f'),
             ('nucleos_ocupados_frac', '%.2f'), ('logica_estatica_W', '%.2f'), ('logica_dinamica_W', '%.2f'),
             ('l2_estatica_W', '%.2f'), ('l2_dinamica_W', '%.2f'), ('parede_s', '%.0f'),
             ('l2_miss_pct_artigo_base', '%.1f')]
    write('medidos', mcols, med,
          '# Valores MEDIDOS (Sniper 8.1 + McPAT 1.0)\n\nUma linha por workload x cenario x tamanho. '
          'Potencia = saida bruta do McPAT (x86, 22 nm), antes da normalizacao da Secao 4.1. '
          'So as linhas com escala_do_artigo = sim usam a entrada do artigo.')

    # ---- projecao para a entrada do artigo
    proj = []
    for w in ('mg', 'xsbench'):
        for s in SCENARIOS:
            t, m = data.get((w, s, 'test')), data.get((w, s, 'mid'))
            if data.get((w, s, 'full')) or not (t or m):
                continue
            bsize, b = ('mid', m) if m else ('test', t)
            f = WORK[w]['full'] / WORK[w][bsize]
            row = {'workload': w, 'cenario': s, 'origem': 'PROJETADO', 'entrada_projetada': INPUT[w]['full'],
                   'base_medida': INPUT[w][bsize], 'fator': f,
                   'instrucoes_roi': b['instrucoes_roi'] * f, 'tempo_simulado_s': b['tempo_simulado_s'] * f,
                   'ipc_agregado': b['ipc_agregado'],
                   'l2_miss_pct': b['l2_miss_pct'] if w == 'xsbench' else 'nao projetado',
                   'l2_miss_pct_medido_na_base': b['l2_miss_pct'],
                   'l2_miss_pct_artigo_base': PAPER_MISS.get((w, s))}
            for k in ('logica_estatica_W', 'logica_dinamica_W', 'l2_estatica_W', 'l2_dinamica_W'):
                row[k] = b[k]
            if all(b[k] is not None for k in ('logica_estatica_W', 'logica_dinamica_W', 'l2_estatica_W', 'l2_dinamica_W')):
                row['energia_J'] = row['tempo_simulado_s'] * sum(
                    b[k] for k in ('logica_estatica_W', 'logica_dinamica_W', 'l2_estatica_W', 'l2_dinamica_W'))
            if b['kips'] and b['parede_s'] is not None:
                pre_roi = max(0.0, b['parede_s'] - b['instrucoes_roi'] / (b['kips'] * 1e3))
                row['parede_estimada_h'] = (row['instrucoes_roi'] / (b['kips'] * 1e3) + pre_roi) / 3600.0
            if t and m:
                ft = WORK[w]['mid'] / WORK[w]['test']
                row['erro_regra_instr_pct'] = 100.0 * (t['instrucoes_roi'] * ft - m['instrucoes_roi']) / m['instrucoes_roi']
                row['erro_regra_tempo_pct'] = 100.0 * (t['tempo_simulado_s'] * ft - m['tempo_simulado_s']) / m['tempo_simulado_s']
                worst = max(abs(row['erro_regra_instr_pct']), abs(row['erro_regra_tempo_pct']))
                row['confianca'] = 'dois pontos medidos' if worst <= 30 else 'baixa (regra errou %.0f%% de test para mid)' % worst
            else:
                row['confianca'] = 'baixa (um ponto medido so: %s)' % bsize
            proj.append(row)
    for row in proj:
        base = next((r for r in proj if r['workload'] == row['workload'] and r['cenario'] == 'a64fx_s'), None)
        row['speedup_vs_a64fx_s'] = base['tempo_simulado_s'] / row['tempo_simulado_s'] if base else None
    pcols = [('workload', '%s'), ('cenario', '%s'), ('origem', '%s'), ('entrada_projetada', '%s'),
             ('base_medida', '%s'), ('fator', '%.0f'), ('instrucoes_roi', '%.3e'), ('tempo_simulado_s', '%.4f'),
             ('speedup_vs_a64fx_s', '%.2f'), ('ipc_agregado', '%.3f'), ('l2_miss_pct', '%.2f'),
             ('l2_miss_pct_medido_na_base', '%.2f'), ('l2_miss_pct_artigo_base', '%.1f'),
             ('logica_estatica_W', '%.2f'), ('logica_dinamica_W', '%.2f'), ('l2_estatica_W', '%.2f'),
             ('l2_dinamica_W', '%.2f'), ('energia_J', '%.3f'), ('parede_estimada_h', '%.1f'),
             ('erro_regra_instr_pct', '%+.1f'), ('erro_regra_tempo_pct', '%+.1f'), ('confianca', '%s')]
    write('projecao', pcols, proj,
          '# PROJECAO para a entrada do artigo (NAO e resultado de simulacao)\n\n'
          'Cada linha = valor medido no tamanho `base_medida` x `fator`. Regras no cabecalho de '
          '`scripts/project_results.py`. `erro_regra_*` = quanto a mesma regra errou ao prever o tamanho '
          'mid a partir do test (positivo = superestimou). MatVecSplit nao aparece: ja foi medido com a '
          'entrada do artigo (ver medidos.md).')

    print('medidos: %d linhas | projecao: %d linhas -> %s' % (len(med), len(proj), os.path.relpath(OUT, ROOT)))
    for r in proj:
        print('  %-8s %-8s x%-5.0f tempo %.4f s  speedup %s  miss %s  [%s]' % (
            r['workload'], r['cenario'], r['fator'], r['tempo_simulado_s'], fmt(r['speedup_vs_a64fx_s'], '%.2f'),
            fmt(r['l2_miss_pct'], '%.2f'), r['confianca']))
    plots(med)


def plots(med):
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError:
        print('matplotlib ausente: graficos nao gerados')
        return
    # um grafico por metrica; em cada workload usa o maior tamanho medido em todos os cenarios
    for col, ylabel, fname in (('l2_miss_pct', 'Miss rate da L2 (%)', 'miss_l2.png'),
                               ('speedup_vs_a64fx_s', 'Speedup sobre A64FX_S (freq. nominal)', 'speedup.png')):
        # por workload: o tamanho com mais cenarios medidos; so entram cenarios com valor
        panels = []
        for w in WORKLOADS:
            size = max(SIZES, key=lambda z: (sum(1 for r in med if r['workload'] == w and r['tamanho'] == z
                                                 and r[col] is not None), SIZES.index(z)))
            rows = {r['cenario']: r[col] for r in med if r['workload'] == w and r['tamanho'] == size and r[col] is not None}
            # MG classe S cabe em qualquer L2 e, em 32 nucleos, e dominado por espera ativa:
            # o grafico dele induziria a erro, entao fica so na tabela.
            if len(rows) >= 2 and not (w == 'mg' and size == 'test'):
                panels.append((w, size, rows))
        if not panels:
            continue
        fig, axes = plt.subplots(1, len(panels), figsize=(4 * len(panels), 3.6), squeeze=False)
        for ax, (w, size, rows) in zip(axes[0], panels):
            names = [s for s in SCENARIOS if s in rows]
            bars = ax.bar(names, [rows[s] for s in names], color='#4c72b0')
            ax.bar_label(bars, fmt='%.2f', fontsize=8)
            missing = [s for s in SCENARIOS if s not in rows]
            ax.set_title('%s\n%s%s' % (w, INPUT[w][size], ('\n(nao medido: %s)' % ', '.join(missing)) if missing else ''),
                         fontsize=8)
            ax.set_ylabel(ylabel, fontsize=8)
            ax.tick_params(labelsize=8)
        fig.suptitle('Medido em escala reduzida (n=1); nao e a entrada do artigo, exceto MatVecSplit', fontsize=9)
        fig.tight_layout()
        fig.savefig(os.path.join(OUT, fname), dpi=150)
        plt.close(fig)
    print('graficos: miss_l2.png, speedup.png')


if __name__ == '__main__':
    main()
