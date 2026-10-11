// BabelStream Triad (a[i] = b[i] + s*c[i]) com ROI do Sniper.
// Uso: ./triad [N_doubles] [iteracoes]   (padrao: 2^24 doubles = 128 MiB/vetor)
#include <cstdio>
#include <cstdlib>
#include <omp.h>
#include "sim_api.h"
int main(int argc, char **argv) {
  size_t n = argc > 1 ? strtoull(argv[1], 0, 10) : (1UL << 24);
  int iters = argc > 2 ? atoi(argv[2]) : 3;
  const double s = 0.4;
  double *a = (double*)aligned_alloc(256, n * sizeof(double));
  double *b = (double*)aligned_alloc(256, n * sizeof(double));
  double *c = (double*)aligned_alloc(256, n * sizeof(double));
  #pragma omp parallel for schedule(static)
  for (size_t i = 0; i < n; i++) { a[i] = 0.1; b[i] = 0.2; c[i] = 0.0; }
  c[0] = 0.0;
  // warmup: uma passada fora da ROI
  #pragma omp parallel for schedule(static)
  for (size_t i = 0; i < n; i++) a[i] = b[i] + s * c[i];
  SimRoiStart();
  for (int it = 0; it < iters; it++) {
    #pragma omp parallel for schedule(static)
    for (size_t i = 0; i < n; i++) a[i] = b[i] + s * c[i];
  }
  SimRoiEnd();
  double chk = 0; for (size_t i = 0; i < n; i += n/16 + 1) chk += a[i];
  printf("triad n=%zu iters=%d threads=%d chk=%g\n", n, iters, omp_get_max_threads(), chk);
  return 0;
}
