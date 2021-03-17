#!/bin/bash
bold=$(tput bold)
normal=$(tput sgr0)
HOST_NAME=`hostname -f`
echo -e "Verification de la commande hostname -f: $HOST_NAME"
echo -e "Veuillez verifier le nom de la machine en cours"

clear
while true; do
   read -p "${bold}Installation de paquets: docker ? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
            zypper -n in docker
            break;;
      [Nn]* ) 
	        echo;
			echo "> Annulation de l'etape.";
			echo;
			break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo
while true; do
   read -p "${bold}Installation du paquet: Docker-distribution-registry? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
        source /etc/os-release
	    if [[ $VERSION_ID =~ "15" ]]; then
		zypper -n in wget
	        wget https://download.opensuse.org/repositories/openSUSE:/Backports:/SLE-15-SP1/standard/x86_64/docker-distribution-registry-2.6.2-bp151.3.3.x86_64.rpm
	        zypper --no-gpg-checks -n in docker-distribution-registry-2.6.2-bp151.3.3.x86_64.rpm
        fi
        if [[ $VERSION_ID =~ "12" ]]; then
            zypper -n in docker-distribution-registry
        fi
        break;;
      [Nn]* ) 
	        echo;
			echo "> Annulation de l'etape.";
			echo;
			break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo
while true; do
   read -p "${bold}Creation d'un certificat dans /etc/registry ? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
            cd /etc/registry
            openssl genrsa 1024 > host.key
            chmod 400 host.key
            openssl req -new -x509 -nodes -sha1 -subj "/CN=$HOST_NAME/C=FR/emailAddress=root@localhost" -days 365 -key host.key -out host.cert
            mkdir -p /etc/docker/certs.d/${HOST_NAME}\:5000/
            cp host.cert /etc/docker/certs.d/${HOST_NAME}\:5000/ca.crt
	        echo
            break;;
      [Nn]* ) 
	        echo;
			echo "> Annulation de l'etape.";
			echo;
			break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo

while true; do
   read -p "${bold}Configuration du certificat pour le registre ? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
	    cat /etc/registry/config.yml|grep "/etc/registry/host.key" > /dev/null
	    if [[ $? != 0 ]]; then
echo "  tls:
    certificate: /etc/registry/host.cert
    key: /etc/registry/host.key"  >> /etc/registry/config.yml
            else 
            echo -e "> Fichier deja configure."
	    echo
            fi
            ls -al /etc/registry/config.yml
	    echo
	    cat /etc/registry/config.yml
            break;;
      [Nn]* ) 
	        echo;
			echo "> Annulation de l'etape.";
			echo;
			break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo
while true; do
   read -p "${bold}Activation et demarrage du service Registry ? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
            systemctl enable registry.service
            systemctl start registry.service
	        systemctl status registry.service
            break;;
      [Nn]* ) 
	        echo;
			echo "> Annulation de l'etape.";
			echo;
			break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo
