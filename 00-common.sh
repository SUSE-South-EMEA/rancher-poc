# Formating
bold=$(tput bold)
normal=$(tput sgr0)
clear

# Create HOSTS variable from file defined in $HOST_LIST_FILE
echo "${TXT_READ_HOST_FILE:=Reading hosts list from file} $HOST_LIST_FILE"
mapfile -t HOSTS < $HOST_LIST_FILE
echo "${TXT_LIST_HOSTS:=List of remote target hosts}:"
echo
printf '%s\n' "${HOSTS[@]}"
echo

# Generic yes/no function
question_yn() {
while true; do
   echo -e "${bold}---\n $1 ${normal}"
   echo -e "${bold}---\n Command:\n ${normal}"
   declare -f $2
   echo
   read -p " ${bold}Execute? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
        $2
        echo
        read -rsp $'Press a key to continue...\n' -n1 key
      break;;
      [Nn]* ) echo "Step canceled";break;;
      * ) echo "Please answer yes (y) or no (n).";;
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
  echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. ERROR!"
  echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
fi
done
}

COMMAND_CHECK_PACKAGE_RPM() {
for h in ${HOSTS[*]}; do
  echo -e "\n${bold}$h${normal}"
  for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
  if ssh $h "sudo rpm -q $i"
  then
    echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
  else
    echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. ERROR!"
    echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
  fi
  done
done
}

COMMAND_CHECK_PACKAGE_DPKG() {
for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
if sudo dpkg-query --show $i
then
  echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
else
  echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. ERROR!"
  echo "sudo dpkg-query --show ${bold}$i${normal}: 'not installed'"
fi
done
}