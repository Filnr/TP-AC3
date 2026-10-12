#!/usr/bin/env python3
"""Adaptador Sniper 8.1 -> McPAT (roda DENTRO do conteiner).

O tools/mcpat.py que acompanha o Sniper ainda le as estatisticas de cache com os
nomes antigos (L1-D.loads, L2.store-misses, ...). O gerenciador de memoria deste
commit (parametric_dram_directory_msi) passou a exporta-las como tloads/tstores/
tload-misses/tstore-misses, entao o mcpat.py original aborta com KeyError.

Este script nao reimplementa nada: importa o mcpat.py original, acrescenta os
nomes antigos como apelidos dos novos e deixa o proprio mcpat.py montar o XML,
chamar o binario do McPAT e interpretar a saida. O McPAT e executado UMA vez; os
tres recortes (total, dinamica, estatica) sao lidos do mesmo power.txt.

Uso: mcpat_sniper.py <dir com sim.cfg e sim.stats.sqlite3> [dir de saida]
Saida: power.xml (entrada do McPAT), power.txt (saida bruta), mcpat_power.json
"""
import json
import os
import sys

SNIPER_ROOT = os.environ.get('SNIPER_ROOT', '/opt/sniper')
sys.path.insert(0, os.path.join(SNIPER_ROOT, 'tools'))

import sniper_lib  # noqa: E402
import mcpat  # noqa: E402

# nome que o mcpat.py espera -> nome que o Sniper 8.1 grava
ALIASES = {
    'loads': 'tloads',
    'stores': 'tstores',
    'load-misses': 'tload-misses',
    'store-misses': 'tstore-misses',
}
CACHES = ('L1-I', 'L1-D', 'L2', 'L3', 'L4', 'nuca-cache')
# TLBs: o MMU novo exporta mmu.tlb_misses_*; com translation_enabled=false (larc_base.cfg)
# esses contadores valem 0, ou seja, o McPAT nao ve atividade de TLB (limitacao documentada).
DIRECT_ALIASES = {
    'itlb.miss': 'mmu.tlb_misses_instruction',
    'dtlb.miss': 'mmu.tlb_misses_data',
}

applied = []
_get_results = sniper_lib.get_results


def get_results_with_aliases(*args, **kwargs):
    res = _get_results(*args, **kwargs)
    stats = res['results']
    for cache in CACHES:
        for old, new in ALIASES.items():
            k_old, k_new = '%s.%s' % (cache, old), '%s.%s' % (cache, new)
            if k_old not in stats and k_new in stats:
                stats[k_old] = stats[k_new]
                if k_old not in applied:
                    applied.append(k_old)
    for k_old, k_new in DIRECT_ALIASES.items():
        if k_old not in stats and k_new in stats:
            stats[k_old] = stats[k_new]
            if k_old not in applied:
                applied.append(k_old)
    return res


sniper_lib.get_results = get_results_with_aliases

# O mcpat.py agrupa em 'other' todo componente abaixo de 1% do total (limiar pensado para o
# grafico de barras). Isso muda o conjunto de componentes de um recorte para outro: a L2 de
# 8 MiB, por exemplo, sumia do recorte 'dynamic' e a sua potencia era somada a logica.
# nocollapse=True devolve sempre todos os componentes, cada um com o seu valor.
_power_stack = mcpat.power_stack
mcpat.power_stack = lambda power_dat, powertype='total', nocollapse=False: \
    _power_stack(power_dat, powertype, nocollapse=True)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    simdir = os.path.abspath(sys.argv[1])
    outdir = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else simdir
    for f in ('sim.cfg', 'sim.stats.sqlite3'):
        if not os.path.isfile(os.path.join(simdir, f)):
            sys.exit('ERRO: %s nao encontrado em %s (a simulacao terminou?)' % (f, simdir))
    os.makedirs(outdir, exist_ok=True)
    base = os.path.join(outdir, 'power')

    out = {'sniper_results_dir': simdir, 'mcpat_binary': mcpat.mcpat_bin()}

    # 1a chamada: gera o XML e roda o McPAT de verdade
    real_run = mcpat.mcpat_run
    status = {}

    def run_and_check(inputfile, outputfile):
        real_run(inputfile, outputfile)
        size = os.path.getsize(outputfile) if os.path.exists(outputfile) else 0
        status['output_bytes'] = size
        if size == 0:
            raise RuntimeError('McPAT nao produziu saida (%s vazio)' % outputfile)

    mcpat.mcpat_run = run_and_check
    data = mcpat.main(0, simdir, base, powertype='total', no_graph=True,
                      print_stack=False, return_data=True)
    out['time_s'] = data['time_s']
    out['ncores'] = data['ncores']

    # chamadas seguintes: reaproveitam o power.txt ja gerado
    mcpat.mcpat_run = lambda inputfile, outputfile: None
    out['power_W'] = {}
    for ptype in ('total', 'dynamic', 'static', 'peak'):
        d = mcpat.main(0, simdir, base, powertype=ptype, no_graph=True,
                       print_stack=False, return_data=True)
        # power_data[0][componente] vem em joules (potencia * tempo)
        out['power_W'][ptype] = {k: v / d['time_s'] for k, v in d['power_data'][0].items()}
    out['stat_aliases_applied'] = applied
    out['mcpat_output_bytes'] = status.get('output_bytes')
    with open(os.path.join(outdir, 'mcpat_power.json'), 'w') as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print('[mcpat_sniper] ok: %s' % os.path.join(outdir, 'mcpat_power.json'))


if __name__ == '__main__':
    main()
