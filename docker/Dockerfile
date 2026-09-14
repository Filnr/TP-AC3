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

# O 'make' baixa Pin (3.31) e, quando necessario, o McPAT automaticamente
# a partir de snipersim.org. Requer rede disponivel durante o build.
RUN make -j"$(nproc)"

WORKDIR /opt/sniper
