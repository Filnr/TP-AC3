// lat.cpp — microbenchmark de latencia de memoria por nivel (pointer chase).
//
// Uso:  ./lat [working_set_bytes] [accesses]
//   16384    -> L1 (64 KiB por nucleo, 4 vias)  : esperado ~3-4 ciclos
//   2097152  -> L2 (8 MiB compartilhada)        : esperado ~37 ciclos (Tabela 1 do artigo)
//   1073741824 -> DRAM (HBM2)                   : esperado ~latencia do [perf_model/dram]
//
// Uma entrada por linha de cache (256 B, o cache_block_size do modelo): cada acesso
// toca exatamente uma linha, entao o footprint e igual a working_set_bytes.
// A permutacao e deterministica (seed fixo), sem reuso, para medir latencia e nao banda.
// Rodar com -n 1 (um nucleo, sem competicao).
#include <cstdio>
#include <cstdlib>
#include <cstddef>
#include "sim_api.h"

static const size_t LINE = 256;   // igual a cache_block_size dos configs

int main(int argc, char **argv) {
  size_t bytes = argc > 1 ? strtoull(argv[1], 0, 10) : (2UL << 20);
  long accesses = argc > 2 ? atol(argv[2]) : 2000000;
  if (bytes < LINE * 4) { fprintf(stderr, "working set muito pequeno\n"); return 1; }
  size_t nlines = bytes / LINE;

  char *buf = (char*)aligned_alloc(256, bytes);
  if (!buf) { perror("aligned_alloc"); return 1; }

  // indice de cada linha
  size_t *order = (size_t*)malloc(nlines * sizeof(size_t));
  for (size_t i = 0; i < nlines; i++) order[i] = i;

  // permutacao deterministica (xorshift64, seed fixo) = chase sem reuso
  unsigned long long s = 0x9E3779B97F4A7C15ULL;
  auto rnd = [&]() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; };
  for (size_t i = nlines - 1; i > 0; i--) {
    size_t j = (size_t)(rnd() % (i + 1));
    size_t t = order[i]; order[i] = order[j]; order[j] = t;
  }

  // cada linha de 256 B guarda, nos seus primeiros 8 bytes, o indice da proxima linha
  for (size_t i = 0; i < nlines; i++)
    *(size_t*)(buf + order[i] * LINE) = order[(i + 1) % nlines];

  size_t start = *(size_t*)(buf + order[0] * LINE);

  volatile size_t sink = 0;
  SimRoiStart();
  size_t p = start;
  for (long a = 0; a < accesses; a++) {
    p = *(size_t*)(buf + p * LINE);   // dependencia de dados: latencia, nao banda
    sink += p;
  }
  SimRoiEnd();

  printf("lat bytes=%zu lines=%zu accesses=%ld sink=%zu\n",
         bytes, nlines, accesses, (size_t)sink);
  free(order);
  free(buf);
  return 0;
}
