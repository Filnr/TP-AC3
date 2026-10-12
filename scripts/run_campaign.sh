#!/usr/bin/env bash
# Campanha experimental do Membro 3: workloads x 4 cenarios x REPS repeticoes, em sequencia.
#
# Por seguranca este script NAO executa nada por padrao: sem --confirm ele apenas lista o que
# seria executado. A campanha completa leva DIAS nesta classe de maquina (ver docs).
#
# Uso:
#   ./scripts/run_campaign.sh                                  # so mostra o plano
#   ./scripts/run_campaign.sh --confirm                        # executa tudo (size full, 3 repeticoes)
#   ./scripts/run_campaign.sh --workloads "mg" --scenarios "a64fx_s larc_a" --reps 1 --confirm
#   ./scripts/run_campaign.sh --size mid --confirm             # ensaio geral reduzido (nao experimental)
#
# Opcoes: --workloads "..."  --scenarios "..."  --reps N (padrao 3)  --size test|mid|full (padrao full)
#         --timeout SEG (repassa para run_workload.sh)  --confirm
# Execucoes ja concluidas (STATUS "OK") do mesmo workload/cenario/size/rep sao puladas, entao a
# campanha pode ser retomada depois de uma interrupcao. Uma falha nao aborta as demais; o resumo
# final lista o que falhou e o codigo de saida e != 0.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

W="${WORKLOADS[*]}"; S="${SCENARIOS[*]}"; REPS=3; SIZE=full; CONFIRM=0; TMO=()
while [ $# -gt 0 ]; do
  case "$1" in
    --workloads) W=${2:?}; shift 2 ;;
    --scenarios) S=${2:?}; shift 2 ;;
    --reps) REPS=${2:?}; shift 2 ;;
    --size) SIZE=${2:?}; shift 2 ;;
    --timeout) TMO=(--timeout "${2:?}"); shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "opcao desconhecida: $1" ;;
  esac
done
[[ "${REPS}" =~ ^[1-9][0-9]*$ ]] || die "--reps invalido: ${REPS}"
for w in ${W}; do [[ " ${WORKLOADS[*]} " == *" ${w} "* ]] || die "workload invalido: ${w}"; done
for s in ${S}; do scenario_cores "${s}" >/dev/null || die "cenario invalido: ${s}"; done

done_already() { # workload cenario rep
  local d
  for d in "${REPO_ROOT}/results/$1/$2/${SIZE}"_*_rep"$3"; do
    [ -f "${d}/STATUS" ] && grep -q '^OK' "${d}/STATUS" && return 0
  done
  return 1
}

echo "Campanha: size=${SIZE}, ${REPS} repeticao(oes); metrica final = mediana das repeticoes (collect_results.py)"
echo "Workloads do artigo: BabelStream e jacobi-2d sao do Membro 2 e NAO sao executados por este script."
TOTAL=0; PENDING=()
for w in ${W}; do for s in ${S}; do for r in $(seq 1 "${REPS}"); do
  TOTAL=$((TOTAL + 1))
  if done_already "$w" "$s" "$r"; then echo "  [feito]    $w / $s / rep $r"
  else echo "  [pendente] $w / $s / rep $r"; PENDING+=("$w $s $r"); fi
done; done; done
echo "${#PENDING[@]} de ${TOTAL} execucoes pendentes."

if [ "${CONFIRM}" != 1 ]; then
  echo
  echo "Nada foi executado. Para iniciar de verdade, repita o comando com --confirm."
  exit 0
fi
[ "${#PENDING[@]}" -gt 0 ] || { echo "Nada a fazer."; exit 0; }

LOG="${REPO_ROOT}/results/_logs/campaign_$(date +%Y%m%d_%H%M%S).log"; mkdir -p "$(dirname "${LOG}")"
log "iniciando ${#PENDING[@]} execucoes; log: ${LOG}"
FAILED=()
for item in "${PENDING[@]}"; do
  read -r w s r <<< "${item}"
  if "${REPO_ROOT}/scripts/run_workload.sh" "$w" "$s" --size "${SIZE}" --rep "$r" "${TMO[@]}" 2>&1 | tee -a "${LOG}"; then :
  else FAILED+=("${item}"); log "FALHOU: ${item} (seguindo para a proxima)" | tee -a "${LOG}"; fi
done
echo
log "campanha encerrada: $(( ${#PENDING[@]} - ${#FAILED[@]} )) ok, ${#FAILED[@]} com falha" | tee -a "${LOG}"
for f in "${FAILED[@]:-}"; do [ -n "$f" ] && echo "  falhou: $f"; done
[ "${#FAILED[@]}" -eq 0 ]
