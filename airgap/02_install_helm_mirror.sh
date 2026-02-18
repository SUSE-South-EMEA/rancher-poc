#!/bin/bash

HOST_NAME=`hostname -f`

question() {
  while true; do
    read -p "${bold} $1 (y/n) ${normal}" yn
    case $yn in
      [Yy]* ) return 0 ;;
      [Nn]* ) return 1 ;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
  done
}

# Part 1: Mirror chart
question "Installer le binaire helm-mirror et nginx ?"
if [[ $? -ne 0 ]]; then echo "Operation annulee" ;
else
    CMD="zypper -n in helm-mirror nginx"
    echo $CMD
    $CMD
    systemctl restart nginx
    systemctl enable nginx
fi

# Download SUSE Chart
question "Mirrorer les charts SUSE dans /srv/www/htdocs/charts ?"
if [[ $? -ne 0 ]]; then echo "Operation annulee" ;
else
    echo "helm-mirror https://kubernetes-charts.suse.com /srv/www/htdocs/charts"
    echo "ETA 1 min"
    helm-mirror --new-root-url http://${HOST_NAME}/charts https://kubernetes-charts.suse.com /srv/www/htdocs/charts
    chown -R nginx:nginx /srv/www/htdocs/charts
fi

# Download Standard Chart
question "Mirrorer les charts Kubernetes 'stable' dans /srv/www/htdocs/stable ?"
if [[ $? -ne 0 ]]; then echo "Operation annulee" ;
else
    echo "helm-mirror https://kubernetes-charts.storage.googleapis.com /tmp/stable-charts"
    echo "ETA 10 min"
    helm-mirror --new-root-url http://${HOST_NAME}/stable https://kubernetes-charts.storage.googleapis.com /srv/www/htdocs/stable
    chown -R nginx:nginx /srv/www/htdocs/stable
fi
