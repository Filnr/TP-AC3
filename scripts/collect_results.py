#!/usr/bin/env python3
"""Consolida os summary.json de results/<workload>/<cenario>/ em uma tabela (CSV + texto).

Uso: ./scripts/collect_results.py [--size full|mid|test] [--out results/summary_<size>.csv]

- Considera apenas execucoes com STATUS "OK" do tamanho pedido (padrao: full).
- Para cada workload x cenario reporta a MEDIANA das repeticoes (Secao 3.3 do artigo) e quantas
  repeticoes entraram (n). Com n < 3 a linha e marcada como incompleta.
- Tamanhos test/mid saem com experimental=nao: servem para validar o fluxo, nao para o artigo.
- speedup_teorico = tempo(A64FX_S) / tempo(cenario), ambos na frequencia nominal (2,2 GHz).
  Speedup "realista", temperatura e throttling NAO sao calculados aqui (modelo termico, Membro 1).
"""
import argparse
import csv
import glob
import json
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIOS = ['a64fx_s', 'a64fx32', 'larc_c', 'larc_a']
WORKLOADS = ['mg', 'xsbench', 'matvecsplit']


def get(d, path):
    for k in path.split('.'):
        if not isinstance(d, dict) or d.get(k) is None:
            return None
        d = d[k]
    return d


METRICS = [  # coluna, caminho no summary.json
    ('tempo_simulado_s', 'sniper.simulated_time_s'),
    ('ipc_agregado', 'sniper.ipc_aggregate'),
    ('l2_miss_rate_pct', 'sniper.l2.miss_rate_pct'),
    ('l2_acessos_por_s', 'sniper.l2.accesses_per_s'),
    ('nucleos_ocupados_frac', 'sniper.core_busy_fraction_avg'),
    ('mcpat_logica_estatica_W', 'mcpat.static.logic_W'),
    ('mcpat_logica_dinamica_W', 'mcpat.dynamic.logic_W'),
    ('mcpat_logica_pico_W', 'mcpat.peak.logic_W'),
    ('mcpat_l2_estatica_W', 'mcpat.static.l2_cache_W'),
    ('mcpat_l2_dinamica_W', 'mcpat.dynamic.l2_cache_W'),
    ('tempo_real_simulacao_s', 'run.sniper_wall_s'),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--size', default='full', choices=['test', 'mid', 'full'])
    ap.add_argument('--out')
    a = ap.parse_args()
    out = a.out or os.path.join(ROOT, 'results', 'summary_%s.csv' % a.size)

    rows = []
    for w in WORKLOADS:
        for s in SCENARIOS:
            runs = []
            for d in sorted(glob.glob(os.path.join(ROOT, 'results', w, s, a.size + '_*'))):
                st = os.path.join(d, 'STATUS')
                sj = os.path.join(d, 'summary.json')
                if os.path.isfile(st) and open(st).read().startswith('OK') and os.path.isfile(sj):
                    runs.append(json.load(open(sj)))
            if not runs:
                continue
            row = {'workload': w, 'cenario': s, 'size': a.size, 'n_repeticoes': len(runs),
                   'experimental': 'sim' if a.size == 'full' else 'nao',
                   'completo': 'sim' if len(runs) >= 3 else 'nao (<3 repeticoes)'}
            for col, path in METRICS:
                vals = [float(v) for v in (get(r, path) for r in runs) if v is not None]
                row[col] = statistics.median(vals) if vals else ''
            rows.append(row)
    if not rows:
        sys.exit('Nenhuma execucao OK de tamanho "%s" em results/.' % a.size)

    base = {r['workload']: r['tempo_simulado_s'] for r in rows if r['cenario'] == 'a64fx_s'}
    for r in rows:
        b = base.get(r['workload'])
        r['speedup_teorico_vs_a64fx_s'] = (b / r['tempo_simulado_s']) if b and r['tempo_simulado_s'] else ''

    cols = list(rows[0].keys())
    with open(out, 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=cols)
        wr.writeheader()
        wr.writerows(rows)

    print('%-12s %-8s %2s %-4s %14s %8s %10s %9s %12s %10s' % (
        'workload', 'cenario', 'n', 'exp', 'tempo_sim(s)', 'IPC', 'missL2(%)', 'speedup', 'logica(W)*', 'L2(W)*'))
    for r in rows:
        f = lambda v, p: (p % v) if v != '' else 'n/d'
        tot = lambda a_, b_: (r[a_] + r[b_]) if r[a_] != '' and r[b_] != '' else ''
        print('%-12s %-8s %2d %-4s %14s %8s %10s %9s %12s %10s' % (
            r['workload'], r['cenario'], r['n_repeticoes'], r['experimental'],
            f(r['tempo_simulado_s'], '%.6f'), f(r['ipc_agregado'], '%.3f'), f(r['l2_miss_rate_pct'], '%.2f'),
            f(r['speedup_teorico_vs_a64fx_s'], '%.2fx'),
            f(tot('mcpat_logica_estatica_W', 'mcpat_logica_dinamica_W'), '%.2f'),
            f(tot('mcpat_l2_estatica_W', 'mcpat_l2_dinamica_W'), '%.2f')))
    print('* potencia bruta do McPAT (x86, 22 nm), ANTES da normalizacao da Secao 4.1.')
    if a.size != 'full':
        print('ATENCAO: size=%s e teste de fluxo; NAO usar estes numeros nas tabelas do artigo.' % a.size)
    print('CSV: %s' % os.path.relpath(out, ROOT))


if __name__ == '__main__':
    main()
