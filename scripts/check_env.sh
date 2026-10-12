#!/usr/bin/env bash
# Verifica o ambiente do Membro 3 sem simular nada. Sai com codigo != 0 se algo obrigatorio faltar.
# Uso: ./scripts/check_env.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FAILS=0
ok()   { echo "  [ok]    $*"; }
warn() { echo "  [aviso] $*"; }
bad()  { echo "  [FALTA] $*"; FAILS=$((FAILS + 1)); }

echo "== Host"
echo "  $(uname -srm) | $(nproc) threads | RAM total $(awk '/MemTotal/{printf "%.1f", $2/1048576}' /proc/meminfo) GiB, disponivel $(awk '/MemAvailable/{printf "%.1f", $2/1048576}' /proc/meminfo) GiB"
grep -qw avx2 /proc/cpuinfo && ok "CPU com AVX2 (flags padrao -mavx2 -mfma)" || bad "CPU sem AVX2: ajuste AVXFLAGS no build"
grep -qw avx512f /proc/cpuinfo && ok "CPU com AVX-512" \
  || warn "CPU sem AVX-512: -mavx512f do artigo NAO pode ser usado (binario roda nativamente sob o SDE)"
AVAIL_GB=$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)
[ "${AVAIL_GB}" -ge 6 ] && ok "memoria disponivel >= 6 GiB" || warn "menos de 6 GiB livres: feche programas antes das execucoes 'full'"
for t in docker git curl tar patch python3; do command -v "$t" >/dev/null && ok "$t" || bad "$t ausente"; done

echo "== Imagem Docker"
if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  ok "${IMAGE_NAME} ($(docker image inspect -f '{{.Id}}' "${IMAGE_NAME}" | cut -c8-19))"
  in_container "" '
    c() { if eval "$2" >/dev/null 2>&1; then echo "  [ok]    $1"; else echo "  [FALTA] $1"; exit 3; fi; }
    echo "  gcc $(gcc -dumpfullversion) | gfortran $(gfortran -dumpfullversion) | $(python3 --version) | $(make --version | head -1)"
    echo "  Sniper: $(grep -m1 "^Version" /opt/sniper/CHANGELOG) (commit $(git -C /opt/sniper rev-parse --short HEAD))"
    c "binario do simulador (lib/sniper)" "test -x /opt/sniper/lib/sniper"
    c "frontend SDE (sde_sift_recorder.so)" "test -f /opt/sniper/sift/recorder/obj-intel64/sde_sift_recorder.so"
    c "McPAT 1.0 (mcpat-1.0.cache executa)" "cd /opt/sniper/mcpat && LD_LIBRARY_PATH=. ./mcpat-1.0.cache 2>&1 | grep -q \"How to use McPAT\""
    c "patch: m_tag_directory_present inicializado" "grep -q \"m_tag_directory_present(false)\" /opt/sniper/common/core/memory_subsystem/parametric_dram_directory_msi/memory_manager.cc"
    c "patch: clone3 sem thread fantasma" "grep -q \"TP-AC3: clone3\" /opt/sniper/sift/recorder/syscall_modeling.cc"
    c "patch: TraceManager sem corrida" "grep -q \"m_threads.reserve(4096)\" /opt/sniper/common/trace_frontend/trace_manager.cc"
    for s in a64fx_s a64fx32 larc_c larc_a power; do c "config montado: $s.cfg" "test -f /opt/sniper/config/$s.cfg"; done
  ' || FAILS=$((FAILS + 1))
else
  bad "imagem ${IMAGE_NAME} nao existe: rode ./scripts/build_image.sh"
fi

echo "== Cenarios (configs/ x Tabela 2 do artigo)"
check_cfg() { # cenario nucleos l2_KiB
  local f="${REPO_ROOT}/configs/$1.cfg"
  [ -f "$f" ] || { bad "$1.cfg ausente"; return; }
  local n l2
  n=$(awk -F= '/^total_cores/{gsub(/[ \t]|#.*/,"",$2); print $2; exit}' "$f")
  l2=$(awk -F= '/^cache_size/{gsub(/[ \t]|#.*/,"",$2); print $2; exit}' "$f")
  [ "$n" = "$2" ] && [ "$l2" = "$3" ] && ok "$1: ${n} nucleos, L2 $((l2 / 1024)) MiB" \
    || bad "$1: esperado $2 nucleos / $3 KiB, encontrado ${n} / ${l2}"
}
check_cfg a64fx_s 12 8192; check_cfg a64fx32 32 8192; check_cfg larc_c 32 262144; check_cfg larc_a 32 524288
grep -q '^frequency = 2.2' "${REPO_ROOT}/configs/larc_base.cfg" && ok "frequencia nominal 2,2 GHz" || bad "frequencia != 2.2 em larc_base.cfg"

echo "== Fontes e binarios dos workloads"
for d in NPB3.4.4 XSBench tapp-kernels; do
  [ -d "${REPO_ROOT}/benchmarks/third_party/$d" ] && ok "fonte: $d" || bad "fonte $d ausente: ./benchmarks/fetch_workloads.sh"
done
for b in mg.S.x mg.W.x mg.B.x XSBench matvecsplit; do
  [ -x "${REPO_ROOT}/benchmarks/bin-m3/$b" ] && ok "binario: $b" || bad "binario $b ausente: ./scripts/build_workloads.sh"
done

echo
if [ "${FAILS}" -eq 0 ]; then echo "Ambiente pronto."; else echo "${FAILS} problema(s) obrigatorio(s) encontrado(s)."; exit 1; fi
