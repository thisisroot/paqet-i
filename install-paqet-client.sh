#!/bin/bash

# Other installation commands...

# ... previous lines ...

# Replacing SOCKS5 listen command
$SUDO_CMD sed -i 's|^\(  - listen: \)".*"|\1"${SOCKS5_LISTEN}"|' /etc/paqet/client.yaml

# ... remaining lines ...