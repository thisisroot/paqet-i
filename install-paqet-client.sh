#!/bin/bash

# Your existing script content here...

# Modified script line
$SUDO_CMD sed -i 's|^\(  - listen: \)".*"|\1"'${SOCKS5_LISTEN}'"|' /etc/paqet/client.yaml

# Your existing script content here...