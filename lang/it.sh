### Common
TXT_END="FINE"
TXT_NEXT_STEP="Prossimo step"
TXT_READ_HOST_FILE="Leggendo la lista degli host dal file"
TXT_LIST_HOSTS="Lista degi target host"
TXT_IS_PRESENT="è presente"
TXT_NOT_PRESENT="è assente"

### Script 01
DESC_CHECK_PACKAGE="Verificare che i pacchetti richiesti siano installati?"
TXT_CHECK_PACKAGE_PRESENT="Controllando che il pacchetto sia installato"
DESC_SSH_KEYS="Creare una coppia di chiavi SSH locale?"
DESC_SSH_DEPLOY="Inviare la chiave pubblica ai nodi?"
TXT_ENTER_CLIENT_PWD="Inserire la password del client"
DESC_SSH_CONNECT_TEST="Testare la connessione SSH ai nodi?"
DESC_COPY_PROXY_CA="Copy proxy private key to clients. Apply parameters ? (specific to SUSE FR Lab)"
DESC_SET_PROXY="variabili PROXY sono settate in ./00-vars.sh. Applicare i parametri? ? \n _HTTP_PROXY=${_HTTP_PROXY} \n _HTTPS_PROXY=${_HTTPS_PROXY} \n _NO_PROXY=${_NO_PROXY}"
DESC_REPOS="Elenco dei repository sui nodi"
DESC_ADDREPOS="Aggiungere i repository containers-modules nel target e nei nodi localion?"
DESC_ADDREPOS_YUM_K8STOOLS="Aggiungere i repository di tool publici di K8S (kubectl....)?"
DESC_NODES_UPDATE="Aggiornare tutti i nodi?"
DESC_CHECK_TIME="Verificare data e ora su tutti i nodi?"
TXT_CHECK_TIME="Non sono presenti Chronyc o ntpq. Non è possibile controllare che l'orario sia sincronizzato correttamente"
DESC_CHECK_ACCESS="Testare l'accesso alle reti pubbliche e di archiviazione da tutti i nodi?"
DESC_DOCKER_INSTALL="Installazione, Attivare e startare Docker su tutti i nodi?"
DESC_DOCKER_INSTALL_YUM="Installazione, Attivare e startare Docker su tutti i nodi?"
DESC_CREATE_DOCKER_USER="Creato utente Docker per RKE\n Docker user: ${DOCKER_USER}\n Docker group: ${DOCKER_GROUP}"
DESC_DOCKER_PROXY="Configure Proxy settings for Docker?"
DESC_IPFORWARD_ACTIVATE="Abilitare IP forwarding?"
DESC_NO_SWAP="Disabilitare lo swap sui target nodes?"
DESC_K8S_TOOLS="Installare kubernetes-client sui nodi locali?"
DESC_FIREWALL="Controllare lo stato del firewall (deve essere disabilitato)?"
DESC_DEFAULT_GW="Verificrea la presenza di un gateway predefinito?"

### Script 02
DESC_RKE_INSTALL="Installare RKE sui nodi locali? \n versione RKE: ${RKE_VERSION}"
DESC_RKE_CONFIG="Creare il file "cluster.yml" di configurazione? \n Kubernetes version: $KUBERNETES_VERSION"
DESC_RKE_DEPLOY="Effettuare il deploy del cluster RKE?"
DESC_KUBECONFIG="Copiare il Kubeconfig file in ~/.kube/config?"
DESC_HELM_INSTALL="Installare HELM? \n Helm Version: ${HELM_VERSION}"
DESC_HELM_REPOS="Aggiungere ghi HELM repository di SUSE + Rancher(Internet!)?"

### Script 03
DESC_CERTMGR_INSTALL="Installare Cert Manager?"
TXT_VERIFY_CERTMGR_INSTALL="Verificando l'installazione di Cert Manager"
DESC_TEST_FQDN="Test DNS name ${LB_RANCHER_FQDN}?"
DESC_RANCHER_INSTALL="Installare il Rancher Management Server (${LB_RANCHER_FQDN})?"
DESC_INIT_ADMIN="Inizializzare la password di admin?"
