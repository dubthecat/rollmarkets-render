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
# Ikemen GO v1.0.0 (MIT engine) with its bundled open-licensed Kung Fu Man characters and stages; the release zip
# unpacks flat (Ikemen_GO_Linux, chars/, data/, external/, font/, stages/). Extra assets are fetched at runtime if IKEMEN_ASSETS is set.
RUN mkdir -p /opt/ikemen && wget -q https://github.com/ikemen-engine/Ikemen-GO/releases/download/v1.0.0/Ikemen_GO-v1.0.0-linux.zip -O /tmp/ik.zip \
    && unzip -q /tmp/ik.zip -d /opt/ikemen && rm /tmp/ik.zip && chmod +x /opt/ikemen/Ikemen_GO_Linux && ls /opt/ikemen \
    && apt-get update && apt-get install -y --no-install-recommends libopenal1 libgtk-3-0 libdecor-0-0 libxrandr2 libxcursor1 libxinerama1 libxi6 libxxf86vm1 libxkbcommon0 libwayland-client0 && rm -rf /var/lib/apt/lists/*
# Red Eclipse 2.0.0 "Jupiter" (zlib engine, CC assets): Linux client + dedicated server + data from the GitHub release
# (bz2 tarball, ~0.9 GB; the bundled SDL/ENet libs live in bin/amd64 and the launchers set LD_LIBRARY_PATH)
RUN apt-get update && apt-get install -y --no-install-recommends bzip2 && rm -rf /var/lib/apt/lists/* \
    && wget -q https://github.com/redeclipse/base/releases/download/v2.0.0/redeclipse_2.0.0_nix.tar.bz2 -O /tmp/re.tar.bz2 \
    && mkdir -p /tmp/re && tar -xjf /tmp/re.tar.bz2 -C /tmp/re && rm /tmp/re.tar.bz2 \
    && d=$(find /tmp/re -maxdepth 3 -name redeclipse.sh -printf '%h\n' | head -1) && mv "$d" /opt/redeclipse && rm -rf /tmp/re \
    && chmod +x /opt/redeclipse/*.sh /opt/redeclipse/bin/amd64/* 2>/dev/null; ls /opt/redeclipse; ls /opt/redeclipse/bin/amd64 \
    && apt-get update && apt-get install -y --no-install-recommends libsdl2-image-2.0-0 libsdl2-mixer-2.0-0 libopenal1 && rm -rf /var/lib/apt/lists/*
COPY render.sh /render.sh
COPY games/ /games/
RUN chmod +x /render.sh /games/*.sh
WORKDIR /work
ENTRYPOINT ["/render.sh"]
