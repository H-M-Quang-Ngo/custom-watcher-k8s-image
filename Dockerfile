FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository cloud-archive:epoxy && \
    apt-get update

# System dependencies and OpenStack libraries
RUN apt-get install -y \
    apache2 \
    libapache2-mod-wsgi-py3 \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    sudo \
    curl \
    wget \
    procps \
    net-tools \
    build-essential \
    git \
    python3-keystoneauth1 \
    python3-keystoneclient \
    python3-oslo.config \
    python3-oslo.db \
    python3-oslo.messaging \
    python3-oslo.log \
    python3-oslo.service \
    python3-pbr \
    python3-pecan \
    python3-wsme \
    python3-sqlalchemy \
    python3-eventlet \
    python3-croniter \
    python3-taskflow \
    python3-stevedore \
    python3-alembic \
    python3-novaclient \
    python3-cinderclient \
    python3-glanceclient \
    python3-neutronclient \
    python3-ironicclient \
    python3-gnocchiclient \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Pebble for service management
RUN curl -s https://api.github.com/repos/canonical/pebble/releases/latest | \
    grep "browser_download_url.*linux_amd64.tar.gz" | \
    cut -d '"' -f 4 | \
    xargs curl -L -o pebble.tar.gz && \
    tar -xzf pebble.tar.gz && \
    mv pebble /bin/pebble && \
    chmod +x /bin/pebble && \
    rm pebble.tar.gz

# Clone and install custom watcher source code
ARG CACHE_BUST=1
RUN git clone --branch review/ho_minh_quang_ngo/enhance-host-maintenance-strategy --single-branch https://github.com/H-M-Quang-Ngo/watcher.git /tmp/watcher-source && \
    pip3 install --break-system-packages /tmp/watcher-source && \
    rm -rf /tmp/watcher-source

# Create watcher user and group
RUN groupadd --gid 42451 watcher 2>/dev/null || true && \
    useradd --uid 42451 --gid 42451 --system --no-create-home --home /var/lib/watcher --shell /bin/false watcher 2>/dev/null || \
    usermod --uid 42451 --gid 42451 --home /var/lib/watcher --shell /bin/false watcher 2>/dev/null || true

# Provide watcher user sudo privileges
RUN echo "watcher ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/watcher && \
    chmod 0440 /etc/sudoers.d/watcher

# Create necessary directories with proper permissions
RUN mkdir -p /var/lib/watcher /var/log/watcher /etc/watcher && \
    chown -R watcher:watcher /var/lib/watcher /var/log/watcher /etc/watcher 2>/dev/null || true

# Create pebble directories for daemon operation
RUN mkdir -p /var/lib/pebble/default && \
    chmod 755 /var/lib/pebble && \
    chmod 755 /var/lib/pebble/default

# Ensure binaries are in the correct location and accessible
RUN ln -sf /usr/local/bin/watcher-* /usr/bin/ 2>/dev/null || true

# Ensure sudo is accessible in /bin for Pebble
RUN test -e /bin/sudo || ln -sf /usr/bin/sudo /bin/sudo

# Ensure sudo is in PATH for all users
ENV PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

EXPOSE 9322

# Set up Pebble entrypoint to match official image
ENTRYPOINT ["/bin/pebble", "enter"]

