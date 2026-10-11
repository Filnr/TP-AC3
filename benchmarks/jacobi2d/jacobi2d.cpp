// jacobi-2d (PolyBench, stencil 5 pontos) paralelizado com OpenMP + ROI do Sniper.
// Uso: ./jacobi2d [N] [TSTEPS]  (padrao: N=2000, TSTEPS=20)
// Conjunto de trabalho: 2 matrizes NxN de double = 2*2000*2000*8 = ~61 MiB.
#include <cstdio>
#include <cstdlib>
#include <omp.h>
#include "sim_api.h"
int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 2000;
  int ts = argc > 2 ? atoi(argv[2]) : 20;
  double *A = (double*)aligned_alloc(256, (size_t)n * n * sizeof(double));
  double *B = (double*)aligned_alloc(256, (size_t)n * n * sizeof(double));
#define A_(i,j) A[(size_t)(i)*n+(j)]
#define B_(i,j) B[(size_t)(i)*n+(j)]
  #pragma omp parallel for schedule(static)
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) {
      A_(i,j) = ((double)i * (j + 2) + 2) / n;
      B_(i,j) = ((double)i * (j + 3) + 3) / n;
    }
  SimRoiStart();
  for (int t = 0; t < ts; t++) {
    #pragma omp parallel for schedule(static)
    for (int i = 1; i < n - 1; i++)
      for (int j = 1; j < n - 1; j++)
        B_(i,j) = 0.2 * (A_(i,j) + A_(i,j-1) + A_(i,j+1) + A_(i+1,j) + A_(i-1,j));
    #pragma omp parallel for schedule(static)
    for (int i = 1; i < n - 1; i++)
      for (int j = 1; j < n - 1; j++)
        A_(i,j) = 0.2 * (B_(i,j) + B_(i,j-1) + B_(i,j+1) + B_(i+1,j) + B_(i-1,j));
  }
  SimRoiEnd();
  printf("jacobi2d n=%d tsteps=%d threads=%d A_(n/2,n/2)=%g\n", n, ts, omp_get_max_threads(), A_(n/2,n/2));
  return 0;
}
