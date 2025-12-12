#!/usr/bin/env bash
set -Eeuo pipefail

# (use existing add_user function)

# Check if the secret file exists and if its size is greater than zero
if [ -s "$secret" ]; then
    PASS=$(cat "$secret")
fi

# Check if config file is not a directory
if [ -d "$config" ]; then

    echo "The bind $config maps to a file that does not exist!"
    exit 1

fi

# Check if an external config file was supplied
if [ -f "$config" ] && [ -s "$config" ]; then

    # Inform the user we are using a custom configuration file.
    echo "Using provided configuration file: $config."

else

    config="/etc/samba/smb.tmp"
    template="/etc/samba/smb.default"

    if [ ! -f "$template" ]; then
      echo "Your /etc/samba directory does not contain a valid smb.conf file!"
      exit 1
    fi

    # Generate a config file from template
    rm -f "$config"
    cp "$template" "$config"

    # Set custom display name if provided
    if [ -n "$NAME" ] && [[ "${NAME,,}" != "data" ]]; then
      sed -i "s/\[Data\]/\[$NAME\]/" "$config"    
    fi

    # Update force user and force group in smb.conf
    sed -i "s/^\(\s*\)force user =.*/\1force user = $USER/" "$config"
    sed -i "s/^\(\s*\)force group =.*/\1force group = $group/" "$config"

    # Verify if the RW variable is equal to false (indicating read-only mode) 
    if [[ "$RW" == [Ff0]* ]]; then
        # Adjust settings in smb.conf to set share to read-only
        sed -i "s/^\(\s*\)writable =.*/\1writable = no/" "$config"
        sed -i "s/^\(\s*\)read only =.*/\1read only = yes/" "$config"
    fi

fi

# Check for an existing passdb.tdb file
if [ "$passdb" ] && [ -s "$passdb" ] ; then
	# if users file is not present, generate a 'fake' one
	# to generate users accounts but preserve passwords
	# file format:' username:*' ...
	if [ -f "$users" ] && [ -s "$users" ]; then
		pdbedit -s "$config" -L |sed -e 's%:.*$%:*%' > "$users"
	fi
fi

# Check if users file is not a directory
if [ -d "$users" ]; then

    echo "The file $users does not exist, please check that you mapped it to a valid path!"
    exit 1

fi

# Check if multi-user mode is enabled
if [ -f "$users" ] && [ -s "$users" ]; then
    uid=10000
    mkdir -p "$home_share" || { echo "Failed to create directory $home_share"; exit 1; }

    while IFS= read -r line || [[ -n ${line} ]]; do

        # Skip lines that are comments or empty
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

        # Split each line by colon and assign to variables
        # IFS=':' read -r username uid groupname gid password homedir <<< "$line"
	# remove 'unnecessary' fields 
        IFS=':' read -r username password <<< "$line"
	# fill 'required' fields
	uid=$(($uid + 1))
	groupname=$username
	gid=$uid
	homedir="$home_share/$username"
        # Check if all required fields are present
        if [[ -z "$username" || -z "$uid" || -z "$groupname" || -z "$gid" || -z "$password" ]]; then
            echo "Skipping incomplete line: $line"
            continue
        fi

        # Default homedir if not explicitly set for user
        [[ -z "$homedir" ]] && homedir="$share"

        # Call the function with extracted values
        add_user "$config" "$username" "$uid" "$groupname" "$gid" "$password" "$homedir" || { echo "Failed to add user $username"; exit 1; }

    done < <(tr -d '\r' < "$users")

else
   # TODO: rethink about 'single user mode' ...

    add_user "$config" "$USER" "$UID" "$group" "$GID" "$PASS" "$share" || { echo "Failed to add user $USER"; exit 1; }

    if [[ "$RW" != [Ff0]* ]]; then
        # Set permissions for share directory if new (empty), leave untouched if otherwise
        if [ -z "$(ls -A "$share")" ]; then
            chmod 0770 "$share" || { echo "Failed to set permissions for directory $share"; exit 1; }
            chown "$USER:$group" "$share" || { echo "Failed to set ownership for directory $share"; exit 1; }
        fi
    fi

fi

