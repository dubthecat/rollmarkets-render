# RollMarkets arena render pod — spectates an AI-vs-AI match of an open-source game on a RunPod GPU,
# encodes it with NVENC and pushes SRT/RTMP to the Fly relay; reports logs and the result to the engine.
# Games: supertuxkart | xonotic | hedgewars | ikemen | test. GPU rendering through VirtualGL's EGL
# back end (no X server needed); falls back to Mesa llvmpipe when the GPU is not reachable.
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive NVIDIA_DRIVER_CAPABILITIES=all TZ=UTC
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb x11-utils x11-xserver-utils xdotool mesa-utils mesa-utils-extra libgl1-mesa-dri libegl1 libglx-mesa0 libglvnd0 \
      ffmpeg fonts-dejavu-core pulseaudio alsa-utils ca-certificates curl wget unzip jq python3 procps \
      supertuxkart supertuxkart-data hedgewars libsdl2-2.0-0 libjpeg-turbo8 libcurl4 \
    && rm -rf /var/lib/apt/lists/*
# Xonotic is not packaged by Ubuntu: the official release zip carries the Linux dedicated server and client
RUN wget -q https://dl.xonotic.org/xonotic-0.8.6.zip -O /tmp/x.zip && unzip -q /tmp/x.zip -d /opt && rm /tmp/x.zip \
    && ln -s /opt/Xonotic/xonotic-linux64-dedicated /usr/local/bin/xonotic-dedicated && ln -s /opt/Xonotic/xonotic-linux64-glx /usr/local/bin/xonotic-glx
# VirtualGL (EGL back end: GPU rendering inside the container, under Xvfb)
RUN wget -qO /tmp/vgl.deb https://github.com/VirtualGL/virtualgl/releases/download/3.1.1/virtualgl_3.1.1_amd64.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/vgl.deb && rm -rf /var/lib/apt/lists/* /tmp/vgl.deb && ls -la /usr/bin/vglrun
# Ikemen GO (MIT engine); characters and stages must be open-licensed and are fetched at runtime if IKEMEN_ASSETS is set
RUN mkdir -p /opt/ikemen && (curl -fsSL https://github.com/ikemen-engine/Ikemen-GO/releases/download/v0.99.0/Ikemen_GO_v0.99.0_Linux.tar.gz | tar -xz -C /opt/ikemen --strip-components=1 || echo "ikemen skipped")
COPY render.sh /render.sh
COPY games/ /games/
RUN chmod +x /render.sh /games/*.sh
WORKDIR /work
ENTRYPOINT ["/render.sh"]
