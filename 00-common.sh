# Formating
bold=$(tput bold)
normal=$(tput sgr0)
clear

# Create HOSTS variable from file defined in $HOST_LIST_FILE
echo "${TXT_READ_HOST_FILE:=Reading hosts list from variable} $HOST_LIST"
echo $HOST_LIST | tr ',' '\n' > hosts.list
mapfile -t HOSTS < hosts.list
echo "${TXT_LIST_HOSTS:=List of remote target hosts}:"
echo
printf '%s\n' "${HOSTS[@]}"
echo

# SSH helper function to use configured SSH_USER
# Usage: ssh_host <host> "<command>"
# Example: ssh_host "node1" "sudo systemctl status docker"
ssh_host() {
    local host="$1"
    local command="$2"
    if [[ -n "${SSH_USER:-}" ]]; then
        ssh "${SSH_USER}@${host}" "$command"
    else
        ssh "$host" "$command"
    fi
}

# SCP helper function to use configured SSH_USER
# Usage: scp_host <source> <host>:<destination> or scp_host <source> <host>:
# Example: scp_host "file.txt" "node1:/tmp/file.txt" or scp_host "file.txt" "node1:"
scp_host() {
    local source="$1"
    local destination="$2"
    if [[ -n "${SSH_USER:-}" ]]; then
        # Extract host from destination (format: host:path or host:)
        if [[ "$destination" =~ ^([^:]+):(.*)$ ]]; then
            local host="${BASH_REMATCH[1]}"
            local path="${BASH_REMATCH[2]}"
            if [[ -n "$path" ]]; then
                scp "$source" "${SSH_USER}@${host}:${path}"
            else
                scp "$source" "${SSH_USER}@${host}:"
            fi
        else
            scp "$source" "$destination"
        fi
    else
        scp "$source" "$destination"
    fi
}

# Generic yes/no function with 3 options: Execute / Skip / Show code
question_yn() {
while true; do
   echo -e "${bold}---\n $1 ${normal}"
   echo
   read -p " ${bold}${TXT_QUESTION_OPTIONS:=Choose an option:} ${normal}${TXT_QUESTION_EXECUTE:=[E]xecute} / ${TXT_QUESTION_SKIP:=[P]asser} / ${TXT_QUESTION_SHOW_CODE:=[C]ode} ${normal}" choice
   echo
   case $choice in
      [Ee]* )
        echo -e "${bold}${TXT_EXECUTING:=Executing...}${normal}"
        $2
        echo
        read -rsp "${TXT_PRESS_KEY_CONTINUE:=Press a key to continue...}" -n1 key
        echo
        break;;
      [PpSs]* ) 
        echo "${TXT_STEP_SKIPPED:=Step skipped.}"
        echo
        break;;
      [Cc]* )
        echo -e "${bold}${TXT_COMMAND_CODE:=Command code:}${normal}"
        declare -f $2
        echo
        continue;;
      * ) 
        echo "${TXT_INVALID_CHOICE:=Invalid choice. Please answer E (Execute), P (Skip) or C (Code).}"
        echo;;
    esac
done
}

## PRE-CHECK PACKAGE
COMMAND_CHECK_PACKAGE_RPM_LOCAL() {
for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
if sudo rpm -q $i
then
  echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
else
  echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
  echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'zypper' ]] ; then
      sudo zypper in -y $i
    elif [[ $pkg_mgr_type == 'yum' ]] ; then
      sudo yum install -y $i
    else
      echo "Package manager should be zypper or yum"
    fi 
fi
done
}

COMMAND_CHECK_PACKAGE_RPM() {
for h in "${HOSTS[@]}"; do
  echo -e "\n${bold}$h${normal}"
  for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
  if ssh_host "$h" "sudo rpm -q $i"
  then
    echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
  else
    echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
    echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'zypper' ]] ; then
      ssh_host "$h" "sudo zypper in -y $i"
    elif [[ $pkg_mgr_type == 'yum' ]] ; then
      ssh_host "$h" "sudo yum install -y $i"
    else
      echo "Package manager should be zypper or yum"
    fi 
  fi
  done
done
}

COMMAND_CHECK_PACKAGE_DPKG_LOCAL() {
for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
if sudo dpkg-query --show $i
then
  echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
else
  echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
  echo "sudo dpkg-query --show ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'apt' ]] ; then
      sudo apt-get install -y $i
    else
      echo "Package manager should be apt"
    fi 
fi
done
}

COMMAND_CHECK_PACKAGE_DPKG() {
for h in "${HOSTS[@]}"; do
  echo -e "\n${bold}$h${normal}"
  for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
  if ssh_host "$h" "sudo dpkg-query --show $i"
  then
    echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
  else
    echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
    echo "sudo dpkg-query --show ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'apt' ]] ; then
      ssh_host "$h" "sudo apt-get install -y $i"
    else
      echo "Package manager should be apt"
    fi 
  fi
  done
done
}
