ARG VARIANT=ubuntu-24.04
FROM mcr.microsoft.com/vscode/devcontainers/base:${VARIANT}

ENV DEBIAN_FRONTEND=noninteractive
ENV PDK_ROOT=/home/vscode/ttsetup/pdk
ENV PDK=sky130A

RUN apt update
RUN apt install -y iverilog gtkwave python3 python3-pip python3-venv python3-tk python-is-python3 libcairo2 verilator libpng-dev libqhull-dev

# Clone tt-support-tools
RUN mkdir -p /ttsetup
RUN git clone https://github.com/TinyTapeout/tt-support-tools /ttsetup/tt-support-tools

COPY test/requirements.txt /ttsetup/test_requirements.txt

RUN python -m venv /ttsetup/venv
RUN /ttsetup/venv/bin/pip install -r /ttsetup/test_requirements.txt -r /ttsetup/tt-support-tools/requirements.txt

# Install verible (for formatting)
RUN umask 022 && \
    curl -L https://github.com/chipsalliance/verible/releases/download/v0.0-4023-gc1271a00/verible-v0.0-4023-gc1271a00-linux-static-x86_64.tar.gz | \
    tar zxf - -C /usr/local --strip-components=1 && \
    chmod 755 /usr/local/bin

# Install LibreLane
RUN /ttsetup/venv/bin/pip install librelane==2.4.2

# setup oh-my-zsh
ARG DOCKER_OHMYZSH_SCRIPT_NAME=zsh-in-docker.sh
ARG DOCKER_OHMYZSH_SCRIPT_URL=https://github.com/deluan/zsh-in-docker/releases/download/v1.1.3/${DOCKER_OHMYZSH_SCRIPT_NAME}
ARG DOCKER_OHMYZSH_SCRIPT_HASH="ffa8175332ef01b500ace59d03ce7e2f3a7453651e9a37060974bb6536f0706b  ${DOCKER_OHMYZSH_SCRIPT_NAME}"
RUN cd /tmp && \
    wget ${DOCKER_OHMYZSH_SCRIPT_URL} && \
    echo ${DOCKER_OHMYZSH_SCRIPT_HASH} | sha256sum -c && \
    chmod +x ./${DOCKER_OHMYZSH_SCRIPT_NAME} && \
    ./${DOCKER_OHMYZSH_SCRIPT_NAME} -t robbyrussell -p git -p ssh-agent && \
    rm ./${DOCKER_OHMYZSH_SCRIPT_NAME}

# build and install Verilator
ARG VERILATOR_VERSION=v5.042
ARG VERILATOR_GIT_REPO=https://github.com/verilator/verilator
RUN sudo apt update && \
    sudo apt-get install -y git help2man perl python3 make autoconf g++ flex bison ccache \
    libgoogle-perftools-dev numactl perl-doc \
    libfl2 \
    libfl-dev \
    zlib1g zlib1g-dev && \
    cd /tmp && \
    git clone --depth=1 --branch ${VERILATOR_VERSION} ${VERILATOR_GIT_REPO} && \
    cd verilator && \
    autoconf && ./configure && make -j `nproc` && sudo make install && \
    cd .. && rm -rf verilator

# install svlint
ARG SVLINT_VERSION=0.9.3
ARG SVLINT_ZIP_NAME=svlint-v${SVLINT_VERSION}-x86_64-lnx.zip
ARG SVLINT_ZIP_URL=https://github.com/dalance/svlint/releases/download/v${SVLINT_VERSION}/${SVLINT_ZIP_NAME}
ARG SVLINT_ZIP_HASH="df44caa38e0cddd09bafa93365d489e47f4823bdda26aa923028c2f06df90456  ${SVLINT_ZIP_NAME}"
RUN mkdir -p /tmp/svlint && \
    cd /tmp/svlint && \
    wget ${SVLINT_ZIP_URL} && \
    echo ${SVLINT_ZIP_HASH} | sha256sum -c && \
    unzip ${SVLINT_ZIP_NAME} && \
    sudo mv bin/* /usr/local/bin/ && \
    cd .. && rm -r /tmp/svlint

# install svls
ARG SVLS_VERSION=0.2.12
ARG SVLS_ZIP_NAME=svls-v${SVLS_VERSION}-x86_64-lnx.zip
ARG SVLS_ZIP_URL=https://github.com/dalance/svls/releases/download/v${SVLS_VERSION}/${SVLS_ZIP_NAME}
ARG SVLS_ZIP_HASH="bebdb42731d3d186c7de4263651f0cf06f346f492b30398a128465f50136f33f  ${SVLS_ZIP_NAME}"
RUN mkdir -p /tmp/svls && \
    cd /tmp/svls && \
    wget ${SVLS_ZIP_URL} && \
    echo ${SVLS_ZIP_HASH} | sha256sum -c && \
    unzip ${SVLS_ZIP_NAME} && \
    sudo mv svls /usr/local/bin/ && \
    cd .. && rm -r /tmp/svls

# install sv2v
ARG SV2V_VERSION=0.0.13
ARG SV2V_ZIP_NAME=sv2v-Linux.zip
ARG SV2V_ZIP_URL=https://github.com/zachjs/sv2v/releases/download/v${SV2V_VERSION}/${SV2V_ZIP_NAME}
ARG SV2V_ZIP_HASH="552799a1d76cd177b9b4cc63a3e77823a3d2a6eb4ec006569288abeff28e1ff8 ${SV2V_ZIP_NAME}"
RUN mkdir /tmp/sv2v && \
    cd /tmp/sv2v && \
    wget ${SV2V_ZIP_URL} && \
    echo ${SV2V_ZIP_HASH} | sha256sum -c && \
    unzip ${SV2V_ZIP_NAME} && \
    chmod +x sv2v-Linux/sv2v && sudo cp sv2v-Linux/sv2v /usr/local/bin && \
    cd .. && rm -r /tmp/sv2v
