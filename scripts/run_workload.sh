#!/usr/bin/env bash
# Executa UM workload do Membro 3 em UM cenario no Sniper e, em seguida, o McPAT.
#
# Uso:
#   ./scripts/run_workload.sh <mg|xsbench|matvecsplit> <a64fx_s|a64fx32|larc_c|larc_a> [opcoes]
#
# Opcoes:
#   --size test|mid|full   tamanho da entrada (padrao: test)
#                            mg:          S (32^3, 4 it) | W (128^3, 4 it) | B (256^3, 20 it)  <- artigo
#                            xsbench:     1e5 lookups    | 1e6 lookups     | 15e6 lookups      <- artigo
#                            matvecsplit: entrada unica do kernel (as tres opcoes sao iguais)
#   --rep N                numero da repeticao, so para rotular a saida (padrao: 1)
#   --timeout SEG          limite da simulacao (padrao: 900 test, 7200 mid, 259200 full)
#   --no-mcpat             nao roda o McPAT ao final
#   --dry-run              mostra o comando e sai, sem simular
#
# Saida: results/<workload>/<cenario>/<size>_<AAAAMMDD_HHMMSS>_rep<N>/   (nunca sobrescreve)
#   command.txt  native.log  sniper.log  sniper/  mcpat/  summary.json  STATUS
#
# Somente --size full corresponde ao experimento do artigo. test/mid validam o fluxo e NAO
# devem entrar nas tabelas (summary.json registra o tamanho usado em run.size).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

[ $# -ge 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; } && usage 0
[ $# -ge 2 ] || usage 1
WORKLOAD=$1; SCENARIO=$2; shift 2
SIZE=test; REP=1; TIMEOUT=""; RUN_MCPAT=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --size) SIZE=${2:?--size exige valor}; shift 2 ;;
    --rep) REP=${2:?--rep exige valor}; shift 2 ;;
    --timeout) TIMEOUT=${2:?--timeout exige valor}; shift 2 ;;
    --no-mcpat) RUN_MCPAT=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "opcao desconhecida: $1 (use --help)" ;;
  esac
done

NCORES=$(scenario_cores "${SCENARIO}") || die "cenario invalido: ${SCENARIO} (use: ${SCENARIOS[*]})"
[ -f "${REPO_ROOT}/configs/${SCENARIO}.cfg" ] || die "configs/${SCENARIO}.cfg nao existe"
case "${SIZE}" in test|mid|full) ;; *) die "--size invalido: ${SIZE} (use test, mid ou full)" ;; esac
[[ "${REP}" =~ ^[0-9]+$ ]] || die "--rep deve ser inteiro: ${REP}"
if [ -z "${TIMEOUT}" ]; then
  case "${SIZE}" in test) TIMEOUT=900 ;; mid) TIMEOUT=7200 ;; full) TIMEOUT=259200 ;; esac
fi
[[ "${TIMEOUT}" =~ ^[0-9]+$ ]] || die "--timeout deve ser inteiro (segundos): ${TIMEOUT}"

BIN_DIR=/work/benchmarks/bin-m3
# OK_PATTERN: linha que o proprio benchmark imprime quando o resultado numerico confere.
# SIG_PATTERN: linha(s) comparadas entre a execucao nativa e a simulada (mesmo resultado).
case "${WORKLOAD}" in
  mg)
    case "${SIZE}" in test) CLS=S ;; mid) CLS=W ;; full) CLS=B ;; esac
    BIN="mg.${CLS}.x"; APP_ARGS=""
    OK_PATTERN='VERIFICATION SUCCESSFUL'; SIG_PATTERN='L2 Norm is' ;;
  xsbench)
    case "${SIZE}" in test) LOOKUPS=100000 ;; mid) LOOKUPS=1000000 ;; full) LOOKUPS=15000000 ;; esac
    # -m event: -l e o TOTAL de lookups (como nas versoes <= v16 usadas no artigo-base);
    # no modo history (padrao da v20) -l seria "lookups por particula".
    BIN="XSBench"; APP_ARGS="-t ${NCORES} -m event -s small -l ${LOOKUPS}"
    # O hash de referencia interno so existe para o numero padrao de lookups; com -l diferente o
    # XSBench imprime "INVALID CHECKSUM" e sai com codigo 1. A validacao aqui e: checksum da
    # execucao simulada == checksum da execucao nativa com os mesmos argumentos.
    OK_PATTERN='Verification checksum:'; SIG_PATTERN='Verification checksum:' ;;
  matvecsplit)
    BIN="matvecsplit"; APP_ARGS=""
    OK_PATTERN='^OK$'; SIG_PATTERN='# result =' ;;
  *) die "workload invalido: ${WORKLOAD} (use: ${WORKLOADS[*]})" ;;
esac
[ -x "${REPO_ROOT}/benchmarks/bin-m3/${BIN}" ] \
  || die "binario benchmarks/bin-m3/${BIN} ausente; rode ./scripts/build_workloads.sh"

STAMP=$(date +%Y%m%d_%H%M%S)
REL_OUT="results/${WORKLOAD}/${SCENARIO}/${SIZE}_${STAMP}_rep${REP}"
OUT="${REPO_ROOT}/${REL_OUT}"
[ -e "${OUT}" ] && die "diretorio de saida ja existe (nao sobrescrevo): ${REL_OUT}"

APP_CMD="${BIN_DIR}/${BIN}${APP_ARGS:+ ${APP_ARGS}}"
# GFORTRAN_UNBUFFERED_ALL=1: sob o Sniper, a saida Fortran que fica em buffer ate o exit() se
# perde em programas multithread (o processo e encerrado antes do flush). So muda a E/S, que
# esta toda fora da ROI; sem isso a linha de verificacao do MG nao chega ao log.
RUN_ENV="OMP_NUM_THREADS=${NCORES} GFORTRAN_UNBUFFERED_ALL=1"
SNIPER_CMD="${RUN_ENV} /opt/sniper/run-sniper -n ${NCORES} -c ${SCENARIO} -c power --roi -d /work/${REL_OUT}/sniper -- ${APP_CMD}"

if [ "${DRY}" = 1 ]; then
  echo "saida:   ${REL_OUT}"
  echo "timeout: ${TIMEOUT} s"
  echo "comando: ${SNIPER_CMD}"
  exit 0
fi

require_docker
mkdir -p "${OUT}"
{
  echo "data:      $(date -Is)"
  echo "workload:  ${WORKLOAD}   cenario: ${SCENARIO}   size: ${SIZE}   rep: ${REP}"
  echo "imagem:    ${IMAGE_NAME} ($(docker image inspect -f '{{.Id}}' "${IMAGE_NAME}"))"
  echo "git:       $(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo n/d) (dirty: $(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null | wc -l) arquivos)"
  echo "host:      $(uname -srm), $(nproc) threads, $(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
  echo "timeout:   ${TIMEOUT} s"
  echo "nativo:    ${RUN_ENV} ${APP_CMD}"
  echo "sniper:    ${SNIPER_CMD}"
} > "${OUT}/command.txt"
echo "EM EXECUCAO" > "${OUT}/STATUS"

CNAME="m3_${WORKLOAD}_${SCENARIO}_${STAMP}_$$"
cleanup() { docker kill "${CNAME}" >/dev/null 2>&1 || true; }
trap 'cleanup; echo "INTERROMPIDO" > "${OUT}/STATUS"; echo; die "interrompido; resultado parcial em ${REL_OUT} NAO e valido"' INT TERM

fail() { echo "FALHOU: $*" > "${OUT}/STATUS"; die "$* (ver ${REL_OUT})"; }

log "${WORKLOAD} / ${SCENARIO} / ${SIZE} / rep ${REP} -> ${REL_OUT}"
T0=$(date +%s)
set +e
in_container "${CNAME}" "
  cd /work/${REL_OUT}
  # 1) referencia nativa (mesmo binario, mesmos argumentos, mesmo numero de threads)
  ${RUN_ENV} timeout 600 ${APP_CMD} > native.log 2>&1; echo \$? > native.rc
  # 2) simulacao
  t0=\$(date +%s)
  ${RUN_ENV} timeout --signal=TERM --kill-after=30 ${TIMEOUT} \
    /opt/sniper/run-sniper -n ${NCORES} -c ${SCENARIO} -c power --roi -d /work/${REL_OUT}/sniper -- ${APP_CMD} > sniper.log 2>&1
  echo \$? > sniper.rc
  echo \$(( \$(date +%s) - t0 )) > sniper.wall_s
"
DOCKER_RC=$?
set -e
trap - INT TERM
[ -f "${OUT}/sniper.rc" ] || fail "conteiner terminou sem executar a simulacao (docker rc=${DOCKER_RC})"

NATIVE_RC=$(cat "${OUT}/native.rc"); SNIPER_RC=$(cat "${OUT}/sniper.rc"); WALL=$(cat "${OUT}/sniper.wall_s")
{ echo "native_rc: ${NATIVE_RC}"; echo "sniper_rc: ${SNIPER_RC}"; echo "sniper_wall_s: ${WALL}"; } >> "${OUT}/command.txt"

# --- validacao (nenhuma etapa abaixo e opcional)
[ "${SNIPER_RC}" != 124 ] && [ "${SNIPER_RC}" != 137 ] || fail "simulacao excedeu o timeout de ${TIMEOUT} s"
# XSBench devolve 1 quando o hash nao e o do caso padrao; todo o resto precisa ser 0.
if [ "${WORKLOAD}" = xsbench ]; then OKRC='^[01]$'; else OKRC='^0$'; fi
[[ "${NATIVE_RC}" =~ ${OKRC} ]] || fail "execucao nativa falhou (rc=${NATIVE_RC}; ver native.log)"
[[ "${SNIPER_RC}" =~ ${OKRC} ]] || fail "run-sniper falhou (rc=${SNIPER_RC}; ver sniper.log)"
grep -aq 'ERROR' "${OUT}/sniper.log" && grep -aq '\*ERROR\*\|\[SNIPER\] ERROR' "${OUT}/sniper.log" \
  && fail "Sniper reportou erro: $(grep -a -m1 '\*ERROR\*\|\[SNIPER\] ERROR' "${OUT}/sniper.log")"
[ -s "${OUT}/sniper/simulation/sim.out" ] || fail "sim.out nao foi gerado"
[ -s "${OUT}/sniper/simulation/sim.stats.sqlite3" ] || fail "sim.stats.sqlite3 nao foi gerado"
grep -aq 'Leaving ROI' "${OUT}/sniper.log" || fail "a ROI nao foi fechada (SimRoiEnd nao alcancado): estatisticas incompletas"
grep -aq "${OK_PATTERN}" "${OUT}/native.log" || fail "verificacao do benchmark ausente na execucao nativa"
grep -aq "${OK_PATTERN}" "${OUT}/sniper.log" || fail "verificacao do benchmark ausente na execucao simulada"
SIG_NATIVE=$(grep -a "${SIG_PATTERN}" "${OUT}/native.log" | tr -s ' ')
SIG_SIM=$(grep -a "${SIG_PATTERN}" "${OUT}/sniper.log" | tr -s ' ')
[ -n "${SIG_SIM}" ] && [ "${SIG_NATIVE}" = "${SIG_SIM}" ] \
  || fail "resultado numerico difere entre nativo e simulado: '${SIG_NATIVE}' vs '${SIG_SIM}'"
log "simulacao ok em ${WALL} s; resultado identico ao nativo: ${SIG_SIM}"
grep -a 'Simulated\|Simulation speed' "${OUT}/sniper.log" | sed 's/^/           /'

# --- McPAT + resumo
MCPAT_NOTE="nao executado (--no-mcpat)"
if [ "${RUN_MCPAT}" = 1 ]; then
  if "${REPO_ROOT}/scripts/run_mcpat.sh" "${REL_OUT}"; then MCPAT_NOTE="ok"; else MCPAT_NOTE="FALHOU"; fi
fi
in_container "" "python3 scripts/result_summary.py ${REL_OUT} workload=${WORKLOAD} scenario=${SCENARIO} \
  size=${SIZE} rep=${REP} sniper_wall_s=${WALL} experimental=$([ "${SIZE}" = full ] && echo true || echo false)" \
  || fail "result_summary.py falhou"

if [ "${MCPAT_NOTE}" = FALHOU ]; then
  echo "PARCIAL: Sniper ok, McPAT falhou" > "${OUT}/STATUS"
  die "McPAT falhou; estatisticas do Sniper validas em ${REL_OUT}, potencia indisponivel"
fi
echo "OK (size=${SIZE}; mcpat: ${MCPAT_NOTE})" > "${OUT}/STATUS"
log "concluido em $(( $(date +%s) - T0 )) s -> ${REL_OUT}/summary.json"
