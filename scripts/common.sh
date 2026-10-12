# Funcoes compartilhadas pelos scripts do Membro 3. Usar com: source scripts/common.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${SNIPER_IMAGE:-larc-thermal-sniper:latest}"
SCENARIOS=(a64fx_s a64fx32 larc_c larc_a)
WORKLOADS=(mg xsbench matvecsplit)

log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { echo "ERRO: $*" >&2; exit 1; }

# Nucleos simulados de cada cenario (Tabela 2 do artigo; conferido contra configs/<cenario>.cfg)
scenario_cores() {
  case "$1" in
    a64fx_s) echo 12 ;;
    a64fx32|larc_c|larc_a) echo 32 ;;
    *) return 1 ;;
  esac
}

require_docker() {
  command -v docker >/dev/null || die "docker nao encontrado no PATH"
  docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1 \
    || die "imagem ${IMAGE_NAME} nao existe; rode ./scripts/build_image.sh"
}

# Roda um comando na imagem do Sniper: repo montado em /work, configs/*.cfg montados
# (somente leitura) em /opt/sniper/config, mesmo UID do host (nada de arquivos do root).
# Uso: in_container <nome-do-conteiner|""> <comando bash>
in_container() {
  local name=$1; shift
  local args=(--rm --init --user "$(id -u):$(id -g)" -e HOME=/tmp -v "${REPO_ROOT}:/work" -w /work)
  [ -n "${name}" ] && args+=(--name "${name}")
  # O Sniper 8.1 fixa TODAS as threads de simulacao numa unica CPU do host (a primeira do conjunto
  # permitido; trace_thread.cc:pinTraceThreadToCPU), entao simulacoes em paralelo disputam a CPU 0.
  # Para rodar varias ao mesmo tempo, dar a cada uma o seu conjunto: M3_CPUSET=4-5 ./scripts/run_workload.sh ...
  [ -n "${M3_CPUSET:-}" ] && args+=(--cpuset-cpus "${M3_CPUSET}")
  local f
  for f in "${REPO_ROOT}"/configs/*.cfg; do
    args+=(-v "${f}:/opt/sniper/config/$(basename "${f}"):ro")
  done
  docker run "${args[@]}" "${IMAGE_NAME}" bash -c "$*"
}
