FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Dependencias de sistema (identicas as usadas no Dockerfile oficial do
# Sniper para Ubuntu 24.04, em github.com/snipersim/snipersim/docker)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-dev \
    python3-venv \
    screen \
    tmux \
    binutils \
    automake \
    build-essential \
    cmake \
    curl \
    wget \
    git \
    libboost-dev \
    libsqlite3-dev \
    zlib1g-dev \
    libbz2-dev \
    libdb++-dev \
    gdb \
    gfortran \
    g++ \
    vim \
 && rm -rf /var/lib/apt/lists/*

# Commit fixado para reprodutibilidade. Nao usar main flutuante.
# Correspondente ao changelog "Version 8.1" no momento em que este
# ambiente foi definido (setembro de 2026).
ARG SNIPER_COMMIT=56505e42fd98bca863fac181e769bd3c98d2bb33

WORKDIR /opt
RUN git clone https://github.com/snipersim/snipersim.git sniper \
 && cd sniper \
 && git checkout ${SNIPER_COMMIT}

WORKDIR /opt/sniper

# Bug conhecido no commit fixado acima: include/sim_api.h inclui
# <unordered_map> (header C++) sem guarda de __cplusplus, o que quebra a
# compilacao de qualquer benchmark escrito em C puro (ex: test/fft) que
# inclua sim_api.h. O include nao e usado em nenhum outro ponto do
# arquivo, entao guardar atras de __cplusplus e seguro.
RUN sed -i \
    's/#include <unordered_map>/#ifdef __cplusplus\n#include <unordered_map>\n#endif/' \
    include/sim_api.h

# O 'make' baixa Pin (3.31) e, quando necessario, o McPAT automaticamente
# a partir de snipersim.org. Requer rede disponivel durante o build.
RUN make -j"$(nproc)"

# Bug no commit fixado: MemoryManager::m_tag_directory_present nunca e
# inicializado no construtor (so m_dram_cntlr_present e). Em nucleos que nao
# sao o 'master' de uma cache compartilhada o membro fica com lixo de memoria
# e a simulacao aborta em memory_manager.cc:391 ("Tag directories may only be
# at 'master' node of shared caches"). Afeta qualquer config multi-core com
# LLC compartilhada (inclusive gainestown -n 4). Camada separada, depois do
# make acima, para a recompilacao ser incremental (1 arquivo + link).
RUN sed -i \
    's/m_dram_cntlr(NULL),/m_dram_cntlr(NULL), m_tag_directory_present(false),/' \
    common/core/memory_subsystem/parametric_dram_directory_msi/memory_manager.cc \
 && grep -q 'm_tag_directory_present(false)' \
    common/core/memory_subsystem/parametric_dram_directory_msi/memory_manager.cc \
 && make -j"$(nproc)"

# Bug no gravador SIFT (frontend SDE) com glibc >= 2.34: pthread_create tenta
# clone3 primeiro; sob Pin/SDE a chamada falha (ENOSYS) e a glibc cai para
# clone. O recorder registra uma thread nova no backend ja na ENTRADA de
# clone3 (antes de saber se deu certo) e de novo na de clone -> todo programa
# multithread ganha 1 thread fantasma (N threads OpenMP viram N+1 no Sniper).
# Com total_cores = N a simulacao aborta ("No cores available for
# spawnThread" / "cannot execute instructions while not on a core") ou trava.
# Correcao: nao registrar nada na entrada de clone3; o clone do fallback
# registra a thread de verdade. Se clone3 um dia passar a funcionar sob o SDE,
# a thread ficaria sem fluxo de traco e a simulacao falharia de forma visivel.
RUN sed -i \
    '/case SYS_clone3_sniper:/,/case SYS_clone:/ s|if (args\[0\] \&\& CLONE_THREAD)|if (false /* TP-AC3: clone3 falha sob SDE, ver docker/Dockerfile */)|' \
    sift/recorder/syscall_modeling.cc \
 && grep -q 'TP-AC3: clone3' sift/recorder/syscall_modeling.cc \
 && make -j"$(nproc)"

# Condicao de corrida no backend: TraceManager::getTraceThread() percorre
# m_threads SEM trava (chamado a cada acesso a memoria por
# MemoryManager::coreInitiateMemoryAccess), enquanto newThread() faz
# m_threads.push_back() ao criar threads. Quando o vector realoca, um leitor
# concorrente le memoria liberada -> "Segmentation fault ... getTraceThread:535"
# logo no inicio de simulacoes com muitas threads (visto com 32 nucleos).
# Reservar a capacidade no construtor elimina a realocacao (push_back passa a
# so escrever o ponteiro e avancar o fim), sem mexer na logica de travas.
RUN sed -i \
    '/^TraceManager::TraceManager()/,/^}/ s|setupTraceFiles(0);|m_threads.reserve(4096); /* TP-AC3: ver docker/Dockerfile */ setupTraceFiles(0);|' \
    common/trace_frontend/trace_manager.cc \
 && grep -q 'm_threads.reserve(4096)' common/trace_frontend/trace_manager.cc \
 && make -j"$(nproc)"

WORKDIR /opt/sniper
