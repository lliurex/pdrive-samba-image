#!/usr/bin/env bash
set -Eeuo pipefail
#
# check for updated samba script

SAMBA_SH="/usr/bin/samba.sh"

[ -e "$SAMBA_SH" ] || SAMBA_SH="/usr/bin/samba-default.sh"

. $SAMBA_SH

