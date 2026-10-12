#!/usr/bin/env python3
"""Resume uma execucao do Sniper (+ McPAT, se houver) em summary.json. Roda DENTRO do conteiner.

Uso: result_summary.py <dir da execucao> [chave=valor ...]   (pares extras vao para "run")

Cada bloco do JSON declara a ORIGEM dos numeros, para nao misturar o que foi simulado,
o que e estimativa do McPAT, o que e constante do artigo e o que e conta feita aqui:
  sniper            -> saida do simulador (ROI apenas)
  mcpat             -> estimativa do McPAT 1.0 (modelo x86 generico, 22 nm, 330 K)
  paper_reference   -> constantes do artigo-base (Domke et al. 2023, Sec. 2.3) / PDF Sec. 4.1
  derived           -> calculado por este script a partir dos blocos acima
"""
import json
import os
import sys

SNIPER_ROOT = os.environ.get('SNIPER_ROOT', '/opt/sniper')
sys.path.insert(0, os.path.join(SNIPER_ROOT, 'tools'))
import sniper_lib  # noqa: E402

# Constantes do artigo-base, por CMG (32 nucleos), no de 1,5 nm.
PAPER = {
    'logic_power_per_cmg_W': 27.37,          # nucleos + interface de memoria de 1 CMG
    'l2_static_power_per_cmg_W': 6.14,       # cache L2 de 384 MiB (NAO 256 nem 512 MiB)
    'l2_capacity_of_reference_MiB': 384,
    'l2_static_basis_W_per_MiB': 0.064 / 4,  # "4 MiB SRAM L2 em 7 nm consome 64 mW estaticos"
    'l2_static_to_dynamic_ratio': 9.0,       # 9:1 (estatica:dinamica), a 350 K
    'l2_reference_temperature_K': 350,
    'cmgs_per_chip': 16,
    'chip_tdp_W': 547.0,                     # 16 x 27,37 (=438) + 16 x 6,14 / 0,9 (=109,23)
    'source': 'Domke et al., ACM TACO 20(4), 2023, Secao 2.3; reproduzido na Secao 4.1 do PDF',
}


def tot(results, key):
    v = results.get(key)
    if v is None:
        return None
    return sum(v) if isinstance(v, list) else v


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    rundir = os.path.abspath(sys.argv[1])
    simdir = os.path.join(rundir, 'sniper', 'simulation')
    if not os.path.isfile(os.path.join(simdir, 'sim.stats.sqlite3')):
        sys.exit('ERRO: %s/sim.stats.sqlite3 nao existe' % simdir)
    res = sniper_lib.get_results(resultsdir=simdir)   # default: roi-begin .. roi-end
    r, cfg = res['results'], res['config']

    ncores = int(cfg['general/total_cores'])
    freq_ghz = float(sniper_lib.sniper_config.get_config(cfg, 'perf_model/core/frequency', 0)) \
        if hasattr(sniper_lib, 'sniper_config') else float(str(cfg['perf_model/core/frequency']).split(',')[0])
    time_s = r['global.time'] * 1e-15
    instr = r['performance_model.instruction_count']
    idle_fs = r.get('performance_model.idle_elapsed_time', [0] * ncores)
    elapsed_fs = r['performance_model.elapsed_time']
    cycles_per_core = time_s * freq_ghz * 1e9
    # Os relogios locais dos nucleos nao estao alinhados com o tempo global na entrada da ROI
    # (quantum da barreira), entao idle pode sair ligeiramente negativo; limita-se a [0, 1].
    busy = [min(1.0, max(0.0, 1.0 - (idle_fs[c] / elapsed_fs[c] if elapsed_fs[c] else 0.0)))
            for c in range(ncores)]

    def cache(name):
        loads, stores = tot(r, name + '.tloads'), tot(r, name + '.tstores')
        lm, sm = tot(r, name + '.tload-misses'), tot(r, name + '.tstore-misses')
        if loads is None:
            return None
        acc, miss = loads + stores, lm + sm
        return {'accesses': acc, 'misses': miss, 'loads': loads, 'stores': stores,
                'miss_rate_pct': (100.0 * miss / acc) if acc else None,
                'accesses_per_s': (acc / time_s) if time_s else None}

    sniper = {
        'origin': 'Sniper %s, regiao de interesse (roi-begin..roi-end)' % res.get('sniper_version', '8.1'),
        'ncores': ncores,
        'frequency_GHz': freq_ghz,
        'l2_size_KiB': int(str(cfg['perf_model/l2_cache/cache_size']).split(',')[0]),
        'l2_shared_cores': int(str(cfg['perf_model/l2_cache/shared_cores']).split(',')[0]),
        'simulated_time_s': time_s,
        'instructions_total': sum(instr),
        'instructions_per_core': instr,
        'ipc_aggregate': sum(instr) / (cycles_per_core * ncores) if time_s else None,
        'core_busy_fraction_avg': sum(busy) / ncores,
        'core_busy_fraction': busy,
        'l1d': cache('L1-D'),
        'l2': cache('L2'),
        'dram_reads': tot(r, 'dram.reads'),
        'dram_writes': tot(r, 'dram.writes'),
    }

    out = {'run': dict(kv.split('=', 1) for kv in sys.argv[2:]), 'sniper': sniper,
           'paper_reference': PAPER}

    l2_mib = sniper['l2_size_KiB'] / 1024.0
    derived = {
        'origin': 'calculado por scripts/result_summary.py; NAO e saida de ferramenta',
        # mesma base do artigo (16 mW/MiB), aplicada a capacidade realmente simulada
        'l2_static_target_scaled_to_simulated_capacity_W': PAPER['l2_static_basis_W_per_MiB'] * l2_mib,
        'l2_dynamic_ceiling_at_9to1_W': PAPER['l2_static_basis_W_per_MiB'] * l2_mib / PAPER['l2_static_to_dynamic_ratio'],
        'note_l2': 'O artigo-base so da 6,14 W para 384 MiB. O valor acima usa a mesma premissa '
                   '(64 mW por 4 MiB) para a L2 deste cenario; usar um OU outro, nunca somar.',
    }

    pfile = os.path.join(rundir, 'mcpat', 'mcpat_power.json')
    if os.path.isfile(pfile):
        p = json.load(open(pfile))['power_W']

        def split(ptype):
            comp = p[ptype]
            l2 = comp.get('l2', 0.0) + comp.get('l3', 0.0) + comp.get('nuca', 0.0)
            dram = comp.get('dram', 0.0)
            logic = sum(v for k, v in comp.items() if k not in ('l2', 'l3', 'nuca', 'dram'))
            return {'logic_W': logic, 'l2_cache_W': l2, 'dram_W': dram, 'components_W': comp}

        out['mcpat'] = {
            'origin': 'McPAT 1.0 via tools/mcpat.py do Sniper (x86 generico, %s nm, 330 K); '
                      'estimativa de modelo, nao medicao' % cfg.get('power/technology_node', '45'),
            'grouping': 'logic = nucleos + L1-I + L1-D + demais blocos do processador; '
                        'l2_cache = L2 compartilhada; dram = modelo DDR3 do mcpat.py (fora do orcamento do artigo)',
            'static': split('static'), 'dynamic': split('dynamic'), 'total': split('total'),
            'peak': split('peak'),
        }
        logic_peak = out['mcpat']['peak']['logic_W']
        logic_tot = out['mcpat']['total']['logic_W']
        derived.update({
            'logic_activity_ratio_total_over_peak': (logic_tot / logic_peak) if logic_peak else None,
            'logic_scale_factor_to_paper_peak': (PAPER['logic_power_per_cmg_W'] / logic_peak) if logic_peak else None,
            'logic_scale_applicable': ncores == 32,
            'note_logic': 'fator = 27,37 W / potencia de PICO da logica no McPAT. So faz sentido para CMG '
                          'de 32 nucleos (27,37 W e o teto de 1 CMG do LARC). Aplicar a normalizacao e papel '
                          'do modelo termico (Membro 1); aqui fica apenas o insumo.',
        })
    else:
        out['mcpat'] = None
    out['derived'] = derived

    with open(os.path.join(rundir, 'summary.json'), 'w') as f:
        json.dump(out, f, indent=2, sort_keys=True)
    l2 = sniper['l2'] or {}
    print('[summary] tempo simulado %.6f s | %.3e instr | IPC agregado %.3f | miss L2 %s%%' % (
        time_s, sum(instr), sniper['ipc_aggregate'] or 0,
        ('%.2f' % l2['miss_rate_pct']) if l2.get('miss_rate_pct') is not None else 'n/d'))
    if out['mcpat']:
        m = out['mcpat']
        print('[summary] McPAT: logica %.2f W (est. %.2f + din. %.2f) | L2 %.2f W (est. %.2f + din. %.2f)' % (
            m['total']['logic_W'], m['static']['logic_W'], m['dynamic']['logic_W'],
            m['total']['l2_cache_W'], m['static']['l2_cache_W'], m['dynamic']['l2_cache_W']))


if __name__ == '__main__':
    main()
