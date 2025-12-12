#!/usr/bin/env bash
set -Eeuo pipefail

# check for updated samba script
SAMBA_SH="/usr/bin/samba.sh"
[ -e "$SAMBA_SH" ] || SAMBA_SH="/usr/bin/samba-default.sh"


# add_user function
# This function checks for the existence of a specified Samba user and group. If the user does not exist, 
# it creates a new user with the provided username, user ID (UID), group name, group ID (GID), and password. 
# If the user already exists, it updates the user's UID and group association as necessary, 
# and updates the password in the Samba database. The function ensures that the group also exists, 
# creating it if necessary, and modifies the group ID if it differs from the provided value.
add_user() {
    local cfg="$1"
    local username="$2"
    local uid="$3"
    local groupname="$4"
    local gid="$5"
    local password="$6"
    local homedir="$7"

    # Check if the smb group exists, if not, create it
    if ! getent group "$groupname" &>/dev/null; then
        [[ "$groupname" != "smb" ]] && echo "Group $groupname does not exist, creating group..."
        groupadd -o -g "$gid" "$groupname" > /dev/null || { echo "Failed to create group $groupname"; return 1; }
    else
        # Check if the gid right,if not, change it
        local current_gid
        current_gid=$(getent group "$groupname" | cut -d: -f3)
        if [[ "$current_gid" != "$gid" ]]; then
            [[ "$groupname" != "smb" ]] && echo "Group $groupname exists but GID differs, updating GID..."
            groupmod -o -g "$gid" "$groupname" > /dev/null || { echo "Failed to update GID for group $groupname"; return 1; }
        fi
    fi

    # Check if the user already exists, if not, create it
    if ! id "$username" &>/dev/null; then
        [[ "$username" != "$USER" ]] && echo "User $username does not exist, creating user..."
        extra_args=()
        # Check if home directory already exists, if so do not create home during user creation
        if [ -d "$homedir" ]; then
          extra_args=("${extra_args[@]}" -H)
        fi
        adduser "${extra_args[@]}" -S -D -h "$homedir" -s /sbin/nologin -G "$groupname" -u "$uid" -g "Samba User" "$username" || { echo "Failed to create user $username"; return 1; }
    else
        # Check if the uid right,if not, change it
        local current_uid
        current_uid=$(id -u "$username")
        if [[ "$current_uid" != "$uid" ]]; then
            echo "User $username exists but UID differs, updating UID..."
            usermod -o -u "$uid" "$username" > /dev/null || { echo "Failed to update UID for user $username"; return 1; }
        fi

        # Update user's group
        usermod -g "$groupname" "$username" > /dev/null || { echo "Failed to update group for user $username"; return 1; }
    fi

    # Check and fix home directory owner/group
    if [ -z "$(find "$homedir" -user "$username" -print -prune -o -prune)" ] || [ -z "$(find "$homedir" -group "$groupname" -print -prune -o -prune)" ] ; then
	    chown -R $username:$groupname $homedir
    fi

    # Check if the user is a samba user
    pdb_output=$(pdbedit -s "$cfg" -L)  #Do not combine the two commands into one, as this could lead to issues with the execution order and proper passing of variables. 
    if echo "$pdb_output" | grep -q "^$username:"; then
        # skip samba password update if password is * or !
        if [[ "$password" != "*" && "$password" != "!" ]]; then
            # If the user is a samba user, update its password in case it changed
            echo -e "$password\n$password" | smbpasswd -c "$cfg" -s "$username" > /dev/null || { echo "Failed to update Samba password for $username"; return 1; }
        fi
    else
        # If the user is not a samba user, create it and set a password
        echo -e "$password\n$password" | smbpasswd -a -c "$cfg" -s "$username" > /dev/null || { echo "Failed to add Samba user $username"; return 1; }
        [[ "$username" != "$USER" ]] && echo "User $username has been added to Samba and password set."
    fi

    return 0
}

# Set variables for group and share directory
group="smb"
share="/storage"
home_share="$share/users"
conf_share="$share/config"
secret="/run/secrets/pass"
config="/etc/samba/smb.conf"
users="/etc/samba/users.conf"
passdb="/var/lib/samba/private/passdb.tdb"

# Create directories if missing
mkdir -p /var/lib/samba/sysvol
mkdir -p /var/lib/samba/private
mkdir -p /var/lib/samba/bind-dns

# Set directory permissions
[ -d /run/samba/msg.lock ] && chmod -R 0755 /run/samba/msg.lock
[ -d /var/log/samba/cores ] && chmod -R 0700 /var/log/samba/cores
[ -d /var/cache/samba/msg.lock ] && chmod -R 0755 /var/cache/samba/msg.lock

# run samba script to:
# - check suplied parameters and (re)assign required vars
# - create users
# - fix permissions and passwords
#
. $SAMBA_SH

# Create shared directory
mkdir -p "$share" || { echo "Failed to create directory $share"; exit 1; }

# check definitive '$config' file
if [ -z "$config" ] || [ ! -s "$config" ] ; then
    echo "Invalid samba config file: $config !"
    exit 1
fi

# Store configuration location for Healthcheck
ln -sf "$config" /etc/samba.conf

# Start the Samba daemon with the following options:
#  --configfile: Location of the configuration file.
#  --foreground: Run in the foreground instead of daemonizing.
#  --debug-stdout: Send debug output to stdout.
#  --debuglevel=1: Set debug verbosity level to 1.
#  --no-process-group: Don't create a new process group for the daemon.
exec smbd --configfile="$config" --foreground --debug-stdout -d "${DEBUG_LEVEL:-1}" --no-process-group

