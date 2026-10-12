#!/usr/bin/env bash
# Roda o McPAT sobre uma execucao ja concluida do Sniper.
#
# Uso: ./scripts/run_mcpat.sh <results/<workload>/<cenario>/<execucao>> [--timeout SEG]
#
# Le   <execucao>/sniper/simulation/{sim.cfg,sim.stats.sqlite3}
# Grava <execucao>/mcpat/{power.xml,power.txt,power.py,mcpat_power.json,mcpat.log,mcpat.rc}
#   power.xml  = entrada do McPAT gerada pelo tools/mcpat.py do Sniper
#   power.txt  = saida bruta do McPAT (-print_level 5)
# Se <execucao>/mcpat ja existir, a anterior e preservada como mcpat.prev_<data>.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ $# -ge 1 ] || die "uso: $0 <diretorio da execucao> [--timeout SEG]"
RUN=${1%/}; shift
TIMEOUT=3600
[ "${1:-}" = "--timeout" ] && TIMEOUT=${2:?--timeout exige valor}
case "${RUN}" in /*) RUN=$(realpath --relative-to="${REPO_ROOT}" "${RUN}") ;; esac
ABS="${REPO_ROOT}/${RUN}"
[ -d "${ABS}" ] || die "diretorio nao existe: ${RUN}"
[ -s "${ABS}/sniper/simulation/sim.stats.sqlite3" ] || die "sem estatisticas do Sniper em ${RUN}/sniper/simulation"
require_docker

[ -d "${ABS}/mcpat" ] && mv "${ABS}/mcpat" "${ABS}/mcpat.prev_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${ABS}/mcpat"

log "McPAT em ${RUN} (timeout ${TIMEOUT} s)"
T0=$(date +%s)
set +e
in_container "" "cd /work/${RUN}/mcpat && timeout ${TIMEOUT} python3 /work/scripts/mcpat_sniper.py \
  /work/${RUN}/sniper/simulation /work/${RUN}/mcpat > mcpat.log 2>&1; echo \$? > mcpat.rc"
set -e
RC=$(cat "${ABS}/mcpat/mcpat.rc" 2>/dev/null || echo 255)
WALL=$(( $(date +%s) - T0 ))
echo "mcpat_wall_s: ${WALL}" >> "${ABS}/mcpat/mcpat.log"

if [ "${RC}" != 0 ]; then
  [ "${RC}" = 124 ] && echo "ERRO: McPAT excedeu ${TIMEOUT} s" >&2
  tail -5 "${ABS}/mcpat/mcpat.log" >&2
  die "McPAT falhou (rc=${RC}); log: ${RUN}/mcpat/mcpat.log"
fi
[ -s "${ABS}/mcpat/power.txt" ] || die "McPAT terminou com rc=0 mas power.txt esta vazio"
grep -q 'Runtime Dynamic' "${ABS}/mcpat/power.txt" || die "power.txt nao contem 'Runtime Dynamic' (saida inesperada do McPAT)"
[ -s "${ABS}/mcpat/mcpat_power.json" ] || die "mcpat_power.json nao foi gerado"
log "McPAT ok em ${WALL} s -> ${RUN}/mcpat/mcpat_power.json"
