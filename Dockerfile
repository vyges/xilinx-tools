FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

LABEL maintainer="Vyges Team" \
      version="2025.1" \
      description="Vivado 2025.1 development environment"

# Configure local ubuntu mirror as package source (optional)
# docker build --build-arg UBUNTU_MIRROR=mirror.example.com/ubuntu -t vyges-vivado .
ARG UBUNTU_MIRROR=""

# Install all required packages in a single RUN command
RUN \
  if [ ! -z "$UBUNTU_MIRROR" ] ; then \
    sed -i -re 's|(http://)([^/]+.*)/|\1'"$UBUNTU_MIRROR"'/|g' /etc/apt/sources.list ; \
  fi && \
  ln -fs /usr/share/zoneinfo/UTC /etc/localtime && \
  apt-get update -y && \
  apt-get upgrade -y && \
  apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    jq \
    less \
    libconfig-dev \
    libpci-dev \
    libsmbios-c2 \
    libtinfo6 \
    libncurses6 \
    locales \
    lsb-release \
    make \
    net-tools \
    pax-utils \
    patch \
    python3-click \
    python3-jinja2 \
    python3-libsmbios \
    python3-pip \
    python3-scapy \
    python3-yaml \
    rsync \
    tcpdump \
    tshark \
    unzip \
    vim-tiny \
    wget \
    wireshark-common \
    zip \
    zstd \
    && \
  pip3 install --break-system-packages pyyaml-include && \
  pip3 install --break-system-packages yq && \
  locale-gen en_US.UTF-8 && \
  update-locale LANG=en_US.UTF-8 && \
  apt-get autoclean && \
  apt-get autoremove && \
  rm -rf /var/lib/apt/lists/*

# Install the Xilinx Vivado tools and updates in headless mode
ENV VIVADO_BASE_VERSION=2025.1
ENV VIVADO_VERSION=${VIVADO_BASE_VERSION}
ARG VIVADO_INSTALLER="FPGAs_AdaptiveSoCs_Unified_SDI_${VIVADO_VERSION}_0530_0145.tar"
ARG VIVADO_UPDATE=""
ARG VIVADO_INSTALLER_CONFIG="/vivado-installer/install_config_vivado.${VIVADO_VERSION}.txt"

# Copy installer files (must be pre-downloaded using download-installer.sh)
COPY vivado-installer/ /vivado-installer/

# Install Vivado
RUN \
  mkdir -p /vivado-installer/install && \
  if [ ! -e /vivado-installer/$VIVADO_INSTALLER ] ; then \
    echo "Error: Installer not found. Please run download-installer.sh first." ; \
    exit 1 ; \
  fi && \
  tar xf /vivado-installer/$VIVADO_INSTALLER --strip-components=1 --no-same-owner -C /vivado-installer/install && \
  if [ ! -e ${VIVADO_INSTALLER_CONFIG} ] ; then \
    echo "No installer configuration file found. Generating default config..." && \
    /vivado-installer/install/xsetup \
      -p 'Vivado' \
      -e 'Vivado ML Enterprise' \
      -b ConfigGen && \
    echo "Generated default configuration:" && \
    echo "-------------" && \
    cat /root/.Xilinx/install_config.txt && \
    echo "-------------" && \
    echo "Using generated configuration for installation..." && \
    VIVADO_INSTALLER_CONFIG="/root/.Xilinx/install_config.txt" ; \
  fi && \
  /vivado-installer/install/xsetup \
    --agree 3rdPartyEULA,XilinxEULA \
    --batch Install \
    --config ${VIVADO_INSTALLER_CONFIG} && \
  rm -r /vivado-installer/install

# Install update if specified
RUN \
  if [ ! -z "$VIVADO_UPDATE" ] ; then \
    mkdir -p /vivado-installer/update && \
    if [ ! -e /vivado-installer/$VIVADO_UPDATE ] ; then \
      echo "Error: Update file not found. Please run download-installer.sh first." ; \
      exit 1 ; \
    fi && \
    tar xf /vivado-installer/$VIVADO_UPDATE --strip-components=1 --no-same-owner -C /vivado-installer/update && \
    /vivado-installer/update/xsetup \
      --agree 3rdPartyEULA,XilinxEULA \
      --batch Update \
      --config ${VIVADO_INSTALLER_CONFIG} && \
    rm -r /vivado-installer/update ; \
  fi

# Clean up installer files
RUN rm -rf /vivado-installer

# Apply post-install patches
COPY patches/ /patches

# Apply Ubuntu-specific patch if available
RUN \
  if [ -e "/patches/ubuntu-$(lsb_release --short --release)-vivado-${VIVADO_VERSION}-postinstall.patch" ] ; then \
    echo "Applying Ubuntu-specific patch for $(lsb_release --short --release)" && \
    patch -p 1 < "/patches/ubuntu-$(lsb_release --short --release)-vivado-${VIVADO_VERSION}-postinstall.patch" ; \
  else \
    echo "No Ubuntu-specific patch found for $(lsb_release --short --release) - skipping" ; \
  fi

# Apply Vivado version-specific patch (required)
RUN \
  if [ -e "/patches/vivado-${VIVADO_VERSION}-postinstall.patch" ] ; then \
    echo "Applying Vivado version-specific patch for ${VIVADO_VERSION}" && \
    patch -p 1 < "/patches/vivado-${VIVADO_VERSION}-postinstall.patch" ; \
  else \
    echo "No Vivado version-specific patch found for ${VIVADO_VERSION}" && \
    exit 1 ; \
  fi

# Set up the container to pre-source the vivado environment
COPY ./entrypoint.sh /entrypoint.sh

# Add health check to verify Vivado installation
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD /tools/Xilinx/${VIVADO_BASE_VERSION}/Vivado/bin/vivado -version > /dev/null 2>&1 || exit 1

ENTRYPOINT [ "/entrypoint.sh" ]

CMD ["/bin/bash", "-l"]

