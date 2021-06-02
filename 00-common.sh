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
