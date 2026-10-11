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
