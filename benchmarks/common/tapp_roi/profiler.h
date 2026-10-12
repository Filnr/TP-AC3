/* Substitui o common/include/profiler.h dos TAPP kernels (que define todos os PROF_*
 * como vazios) para que PROF_START/PROF_STOP -- os marcadores que os autores do kernel
 * colocaram em volta da secao cronometrada -- virem a ROI do Sniper.
 * Entra por -I antes do diretorio original; o fonte do kernel nao e alterado. */
#ifndef TAPP_ROI_PROFILER_H
#define TAPP_ROI_PROFILER_H
#include "sim_api.h"
#define PROF_INIT
#define PROF_FINALIZE
#define PROF_START_ALL
#define PROF_STOP_ALL
#define PROF_START(name) SimRoiStart()
#define PROF_STOP(name) SimRoiEnd()
#endif
