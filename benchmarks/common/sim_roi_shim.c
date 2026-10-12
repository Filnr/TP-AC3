/* Marcadores de ROI do Sniper chamaveis a partir de Fortran.
 * SimRoiStart()/SimRoiEnd() (include/sim_api.h do Sniper) sao macros com assembly
 * inline ("magic instruction"), entao nao podem ser chamadas direto do Fortran.
 * O gfortran procura simbolos em minusculas com '_' no final.
 * Fora do simulador a instrucao magica e um no-op (xchg %bx,%bx). */
#include "sim_api.h"

void sim_roi_start_(void) { SimRoiStart(); }
void sim_roi_end_(void) { SimRoiEnd(); }
