#!/usr/bin/env bash
# Teste preliminar da Etapa 2: compila e roda test/fft sob o Sniper dentro
# do container, e extrai o log basico para results/, comprovando que o
# ambiente do simulador esta validado e funcional.
#
# Uso: ./scripts/run_preliminary_test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="larc-thermal-sniper:latest"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${REPO_ROOT}/results/preliminary_${STAMP}"

mkdir -p "${OUT_DIR}"

docker run --rm \
  -v "${OUT_DIR}:/out" \
  "${IMAGE_NAME}" \
  bash -c '
    set -e
    cd /opt/sniper/test/fft
    make
    ../../run-sniper -v -n 1 -c gainestown --roi -- ./fft -p 1 2>&1 | tee /out/run.log
    cp sim.out /out/sim.out 2>/dev/null || true
    cp -r sim.stats.sqlite3 /out/ 2>/dev/null || true
  '

echo "Log do teste preliminar salvo em: ${OUT_DIR}"
