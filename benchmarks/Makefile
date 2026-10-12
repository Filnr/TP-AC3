# Compilar dentro do nix-shell (Sniper em $SNIPER_HOME). Flags conforme a Secao 3.3 do artigo.
#
# AVX-512: o artigo pede -mavx512f -mavx512cd, mas meu cpu (i7-13700KF) NAO tem AVX-512
# (lscpu: nenhuma flag avx512*). Pin executa o binario nativamente, entao -mavx512f
# geraria Illegal instruction. Compilamos com -mavx2 -mfma (equivalente de 256 bits)
SNIPER ?= $(SNIPER_HOME)
AVXFLAGS ?= -mavx2 -mfma
CXXFLAGS = -O3 $(AVXFLAGS) -fopenmp -I$(SNIPER)/include
all: bin/triad bin/jacobi2d bin/lat
bin/triad: babelstream/triad.cpp | bin
	$(CXX) $(CXXFLAGS) $< -o $@
bin/jacobi2d: jacobi2d/jacobi2d.cpp | bin
	$(CXX) $(CXXFLAGS) $< -o $@
bin/lat: microbench/lat.cpp | bin
	$(CXX) $(CXXFLAGS) $< -o $@
bin:
	mkdir -p bin
clean:
	rm -rf bin

# ---------------------------------------------------------------------------------------------
# Workloads do Membro 3 (NPB MG-OMP, XSBench, MatVecSplit). Fontes oficiais em third_party/,
# baixados por ./fetch_workloads.sh. Compilar DENTRO do conteiner: ../scripts/build_workloads.sh
# Mesmas flags dos alvos acima (-O3 $(AVXFLAGS) -fopenmp); nada de -ffast-math, para manter as
# verificacoes numericas internas dos benchmarks validas.
# ---------------------------------------------------------------------------------------------
TP      := $(CURDIR)/third_party
NPB     := $(TP)/NPB3.4.4/NPB3.4-OMP
XSB     := $(TP)/XSBench/openmp-threading
ADV     := $(TP)/tapp-kernels/tapp-kernels/Adventure.region0.20170821
OPTFLAGS = -O3 $(AVXFLAGS) -fopenmp
MG_CLASSES ?= S W B
# Diretorio proprio: benchmarks/bin/ foi criado por um conteiner rodando como root e nao e
# gravavel pelo usuario do host; os scripts do Membro 3 rodam o conteiner com o UID do host.
WBIN    ?= bin-m3

workloads: mg xsbench matvecsplit
mg: $(foreach c,$(MG_CLASSES),$(WBIN)/mg.$(c).x)
xsbench: $(WBIN)/XSBench
matvecsplit: $(WBIN)/matvecsplit

build/sim_roi_shim.o: common/sim_roi_shim.c | build
	$(CC) -O2 -I$(SNIPER)/include -c $< -o $@

# O NPB gera npbparams.h por classe (sys/setparams) e exige config/make.def.
# S (32^3) e W (128^3) servem so para validacao; B (256^3, 20 iteracoes) e a do artigo.
$(WBIN)/mg.%.x: build/sim_roi_shim.o $(NPB)/MG/mg.f90 | $(WBIN)
	@printf '%s\n' 'FC = gfortran' 'FLINK = $$(FC)' 'F_LIB = $(CURDIR)/build/sim_roi_shim.o' 'F_INC =' \
	  'FFLAGS = $(OPTFLAGS)' 'FLINKFLAGS = $$(FFLAGS)' 'CC = gcc' 'CLINK = $$(CC)' 'C_LIB = -lm' 'C_INC =' \
	  'CFLAGS = $(OPTFLAGS)' 'CLINKFLAGS = $$(CFLAGS)' 'UCC = gcc' 'BINDIR = ../bin' 'RAND = randi8' \
	  'WTIME = wtime.c' > $(NPB)/config/make.def
	$(MAKE) -C $(NPB) clean >/dev/null
	$(MAKE) -C $(NPB) mg CLASS=$*
	cp $(NPB)/bin/mg.$*.x $@

# Flags do Makefile oficial (openmp-threading: -std=gnu99 -Wall -flto -fopenmp -DOPENMP -O3)
# + AVXFLAGS + -DSNIPER_ROI (liga os marcadores do patches/xsbench-roi.patch).
$(WBIN)/XSBench: $(wildcard $(XSB)/*.c) $(XSB)/XSbench_header.h | $(WBIN)
	$(CC) -std=gnu99 -Wall -flto $(OPTFLAGS) -DOPENMP -DSNIPER_ROI -I$(SNIPER)/include \
	  $(wildcard $(XSB)/*.c) -o $@ -lm

# TAPP kernel 17 (ADVENTURE region0, MatVec_product). Fonte NAO modificado: common/tapp_roi vem
# antes no -I e troca PROF_START/PROF_STOP pela ROI do Sniper. Sem __ARM_FEATURE_SVE o proprio
# fonte usa o caminho C escalar (autovetorizado pelo GCC). Validacao interna mantida.
$(WBIN)/matvecsplit: $(ADV)/adventure_kernel_region0_tune4_arm_pad-acle.c common/tapp_roi/profiler.h | $(WBIN)
	$(CC) -std=gnu99 $(OPTFLAGS) -include $(ADV)/common/include/report.h -Icommon/tapp_roi -I$(SNIPER)/include -I$(ADV)/common/include \
	  $< $(ADV)/common/src/report.c -o $@ -lm

build $(WBIN):
	mkdir -p $@
clean-workloads:
	rm -rf build $(WBIN)
.PHONY: all clean workloads mg xsbench matvecsplit clean-workloads
