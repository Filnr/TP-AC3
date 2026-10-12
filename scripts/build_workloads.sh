#!/usr/bin/env bash
# Compila os workloads do Membro 3 dentro do conteiner do Sniper (mesmo GCC/gfortran/glibc
# usados na simulacao) e confere que os binarios existem e sao executaveis.
#
# Uso: ./scripts/build_workloads.sh [mg|xsbench|matvecsplit|workloads]   (padrao: workloads)
#      AVXFLAGS="-mavx2 -mfma" MG_CLASSES="S W B" ./scripts/build_workloads.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARGET="${1:-workloads}"
case "${TARGET}" in mg|xsbench|matvecsplit|workloads) ;; *) die "alvo invalido: ${TARGET} (use mg, xsbench, matvecsplit ou workloads)";; esac
require_docker
[ -d "${REPO_ROOT}/benchmarks/third_party/XSBench" ] && [ -d "${REPO_ROOT}/benchmarks/third_party/NPB3.4.4" ] \
  && [ -d "${REPO_ROOT}/benchmarks/third_party/tapp-kernels" ] \
  || die "fontes ausentes; rode ./benchmarks/fetch_workloads.sh primeiro"

AVXFLAGS="${AVXFLAGS:--mavx2 -mfma}"
MG_CLASSES="${MG_CLASSES:-S W B}"
LOG_DIR="${REPO_ROOT}/results/_logs"; mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"

log "compilando '${TARGET}' com AVXFLAGS='${AVXFLAGS}' (log: ${LOG})"
if ! in_container "" "gcc --version | head -1; gfortran --version | head -1; \
    make -C benchmarks ${TARGET} SNIPER=/opt/sniper AVXFLAGS='${AVXFLAGS}' MG_CLASSES='${MG_CLASSES}'" > "${LOG}" 2>&1; then
  tail -30 "${LOG}" >&2
  die "compilacao falhou (log completo: ${LOG})"
fi

expected=()
case "${TARGET}" in
  mg|workloads) for c in ${MG_CLASSES}; do expected+=("mg.${c}.x"); done ;;&
  xsbench|workloads) expected+=(XSBench) ;;&
  matvecsplit|workloads) expected+=(matvecsplit) ;;
esac
for b in "${expected[@]}"; do
  [ -x "${REPO_ROOT}/benchmarks/bin-m3/${b}" ] || die "binario esperado nao foi gerado: benchmarks/bin-m3/${b}"
  log "ok: benchmarks/bin-m3/${b} ($(stat -c %s "${REPO_ROOT}/benchmarks/bin-m3/${b}") bytes)"
done
