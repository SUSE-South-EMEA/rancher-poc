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
            yum install -y docker
	    systemctl enable --now docker
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
   read -p "${bold}Installation du paquet: docker-registry? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
        yum install -y docker-registry
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
   read -p "${bold}Creation d'un certificat dans /etc/docker-distribution/registry ? (y/n) ${normal}" yn
   case $yn in
      [Yy]* )
            cd /etc/docker-distribution/registry
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
	    cat /etc/docker-distribution/registry/config.yml|grep "/etc/docker-distribution/registry/host.key" > /dev/null
	    if [[ $? != 0 ]]; then
echo "    tls:
      certificate: /etc/docker-distribution/registry/host.cert
      key: /etc/docker-distribution/registry/host.key"  >> /etc/docker-distribution/registry/config.yml
            else 
            echo -e "> Fichier deja configure."
	    echo
            fi
            ls -al /etc/docker-distribution/registry/config.yml
	    echo
	    cat /etc/docker-distribution/registry/config.yml
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
            systemctl enable docker-distribution.service
            systemctl start docker-distribution.service
	        systemctl status docker-distribution.service
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
