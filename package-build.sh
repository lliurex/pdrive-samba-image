#!/bin/sh
POD_IMAGE="docker.io/lliurex/pdrive-samba:latest"
PODMAN_CMD="podman --events-backend 'none'"

POD_FILE="pdrive-samba"
[ -z "$1" ] || POD_FILE="$1"

$PODMAN_CMD pull --tls-verify=false "$POD_IMAGE"
$PODMAN_CMD inspect "$POD_IMAGE" |grep 'Created' |cut -f 2 -d ':' |sed -e 's%^.*\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}\).*$%\1%' > "$POD_FILE.version"
$PODMAN_CMD  save -o "$POD_FILE.tar" "$POD_IMAGE"
$PODMAN_CMD image rm "$POD_IMAGE"

