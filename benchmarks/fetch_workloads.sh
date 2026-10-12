#!/usr/bin/env bash
# Baixa os fontes oficiais dos workloads do Membro 3 em benchmarks/third_party/
# (nao versionado) em versoes FIXAS e aplica os patches de ROI de benchmarks/patches/.
# Idempotente: pode ser executado de novo sem baixar nem aplicar patch duas vezes.
#
# Uso: ./benchmarks/fetch_workloads.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TP="${HERE}/third_party"

NPB_VERSION="3.4.4"
NPB_URL="https://www.nas.nasa.gov/assets/npb/NPB${NPB_VERSION}.tar.gz"
NPB_SHA256="1ae219398e02a0a79ad51b7460fcffbf7b5df83a69d5d3d3a9dc2d8acf523549"
XSBENCH_URL="https://github.com/ANL-CESAR/XSBench.git"
XSBENCH_COMMIT="ba08e5221af6106252b866e50ea123c69d31a4e2"   # v20 + 24 commits (2024-03-11)
TAPP_URL="https://github.com/RIKEN-RCCS/fs2020-tapp-kernels.git"
TAPP_COMMIT="112d97e1f8055bd68710b6348362ac83de9f83d5"      # 2022-11-22

die() { echo "ERRO: $*" >&2; exit 1; }
for t in git curl tar patch sha256sum; do
  command -v "$t" >/dev/null || die "ferramenta ausente no host: $t"
done
mkdir -p "${TP}"

clone_at() { # url dir commit
  local url=$1 dir=$2 commit=$3
  if [ ! -d "${dir}/.git" ]; then
    echo "[fetch] clonando ${url}"
    git clone -q "${url}" "${dir}"
  fi
  if [ "$(git -C "${dir}" rev-parse HEAD)" != "${commit}" ]; then
    git -C "${dir}" diff --quiet || die "${dir} tem alteracoes locais; nao vou trocar de commit por cima delas"
    git -C "${dir}" checkout -q "${commit}"
  fi
  echo "[fetch] $(basename "${dir}") em $(git -C "${dir}" rev-parse --short HEAD)"
}

apply_once() { # dir patchfile -pN
  local dir=$1 pf=$2 strip=$3
  if patch -d "${dir}" "${strip}" -R --dry-run -s -f < "${pf}" >/dev/null 2>&1; then
    echo "[fetch] patch ja aplicado: $(basename "${pf}")"
  else
    patch -d "${dir}" "${strip}" -N -s < "${pf}" || die "falha ao aplicar $(basename "${pf}")"
    echo "[fetch] patch aplicado: $(basename "${pf}")"
  fi
}

# --- NPB (tarball oficial da NASA, conferido por SHA-256)
if [ ! -d "${TP}/NPB${NPB_VERSION}" ]; then
  [ -f "${TP}/NPB${NPB_VERSION}.tar.gz" ] || curl -sSfL -o "${TP}/NPB${NPB_VERSION}.tar.gz" "${NPB_URL}"
  echo "${NPB_SHA256}  ${TP}/NPB${NPB_VERSION}.tar.gz" | sha256sum -c --quiet - \
    || die "SHA-256 do NPB nao confere"
  tar -xzf "${TP}/NPB${NPB_VERSION}.tar.gz" -C "${TP}"
fi
echo "[fetch] NPB ${NPB_VERSION}"
apply_once "${TP}/NPB${NPB_VERSION}" "${HERE}/patches/npb-mg-roi.patch" -p0

# --- XSBench
clone_at "${XSBENCH_URL}" "${TP}/XSBench" "${XSBENCH_COMMIT}"
apply_once "${TP}/XSBench" "${HERE}/patches/xsbench-roi.patch" -p1

# --- TAPP kernels (MatVecSplit = Adventure.region0; ROI entra por -I, sem patch)
clone_at "${TAPP_URL}" "${TP}/tapp-kernels" "${TAPP_COMMIT}"

echo "[fetch] fontes prontos em ${TP}"
