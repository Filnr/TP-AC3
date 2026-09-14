# Infraestrutura - Avaliacao de Restricoes Termicas em Cache 3D Empilhada

Ambiente de simulacao usado no artigo, baseado no simulador Sniper.

## Ambiente

O simulador roda em container Docker para garantir que os cinco integrantes
usem exatamente o mesmo ambiente, independente do sistema operacional local
de cada um. Nao ha dependencia de GPU; o Sniper e um simulador de timing
que roda inteiramente em CPU.

Commit do Sniper fixado para reprodutibilidade:
`56505e42fd98bca863fac181e769bd3c98d2bb33` (Version 8.1 no CHANGELOG oficial,
https://github.com/snipersim/snipersim).

Licenca do Sniper: academica, uso restrito a pesquisa nao comercial
(ver `LICENSE.academic` no repositorio oficial).

## Requisitos

Docker instalado no host. Nenhum outro requisito local, o sistema
operacional do host nao importa.

## Uso

Construir a imagem:

    ./scripts/build_image.sh

Rodar o teste preliminar da Etapa 2 (benchmark fft, roda em segundos):

    ./scripts/run_preliminary_test.sh

O log e as estatisticas ficam em `results/preliminary_<timestamp>/`.

## Estrutura

    docker/       Dockerfile do ambiente
    scripts/      scripts de build e execucao
    results/      saida dos testes (versionada, evidencia para a secao
                  de Metodologia sobre validacao do ambiente)

## Proximos passos (fora do escopo deste script)

Configuracao dos cenarios de cache (controle A64FX, LARC_C, LARC_A) e
integracao com McPAT para extracao de potencia ficam nos scripts dos
membros responsaveis por Metodologia, a serem adicionados neste mesmo
repositorio em pastas separadas quando prontos.
