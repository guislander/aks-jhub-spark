# create aks cluster for jupyterhub
#
LTPURPLE='\033[1;35m'
NC='\033[0m'

RESOURCEGROUP=myjhub
CLUSTERNAME=myjhub

mkdir $CLUSTERNAME
cd $CLUSTERNAME
echo -e "\n${LTPURPLE}Created directory `pwd`${NC}"

#
# enable aks auto scaling preview
#
# az extension add --name aks-preview
# az feature register --name VMSSPreview --namespace Microsoft.ContainerService
# az feature list   --output table   --query  "[?contains(name, 'Microsoft.ContainerService/VMSSPreview')].{Name:name,State:properties.state}"
# az provider register --namespace Microsoft.ContainerService

#
# create az resource group
#
echo -e "\n${LTPURPLE}Creating resource group${NC}"
az group create --name $RESOURCEGROUP \
                --location centralus \
		--output table

#
# create cluster
#
echo -e "\n${LTPURPLE}Creating cluster ssh key${NC}"
ssh-keygen -q -f ssh-key-$CLUSTERNAME -N `openssl rand -hex 6`
echo -e "\n${LTPURPLE}Creating aks cluster...this will take several minutes${NC}"
az aks create --name $CLUSTERNAME \
              --resource-group $RESOURCEGROUP \
              --ssh-key-value ssh-key-$CLUSTERNAME.pub \
              --node-count 1 \
              --node-vm-size Standard_D2s_v3 \
              --enable-vmss \
              --enable-cluster-autoscaler \
              --min-count 1 \
              --max-count 6 \
	      --output table

#
# get credentials
#
echo -e "\n${LTPURPLE}Getting cluster credentials${NC}"
az aks get-credentials --name $CLUSTERNAME \
                       --resource-group $RESOURCEGROUP 


#
# creat jhub config
#
echo -e "\n${LTPURPLE}Creating helm config for jupyterhub with pyspark aks notebook${NC}"
echo -e "proxy:
  secretToken: \"`openssl rand -hex 32`\"

hub:
  extraConfig:
    config.py: |
      from kubespawner import KubeSpawner
      from tornado import gen
      import yaml

      class CustomKubeSpawner(KubeSpawner):
        @gen.coroutine
        def start(self):
          self.common_labels = {
            'app': 'jhub-sparkdriver'
          }  
          self.service_account = 'spark'

          return (yield super().start())

      c.JupyterHub.spawner_class = CustomKubeSpawner

singleuser:
  image:
    name: guislander/spark-aks-notebook
    tag: v2.4.4
  storage:
    dynamic:
      storageClass: managed-premium
" >config.yaml

#
# install jupyterhub
#
echo -e "\n${LTPURPLE}Adding jupyterhub to helm repo${NC}"
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

# Suggested values: advanced users of Kubernetes and Helm should feel
# free to use different values.
RELEASE=jhub
NAMESPACE=jhub
echo -e "\n${LTPURPLE}Deploying jupyterhub node service..this will take several minutes.${NC}"
kubectl create namespace $NAMESPACE
helm install $RELEASE jupyterhub/jupyterhub \
  --namespace $NAMESPACE  \
  --version=0.8.2 \
  --values config.yaml \
  --timeout 15m

# wating for pods
#
echo -e "\n${LTPURPLE}Wating for hub and proxy pods to run${NC}"
x=`/usr/local/bin/kubectl --namespace=$NAMESPACE get pod | grep -e proxy -e hub | tr ' ' '\n' | grep -c Running`
while [$x -le 2] 
do
  x = `/usr/local/bin/kubectl --namespace=$NAMESPACE get pod | grep -e proxy -e hub | tr ' ' '\n' | grep -c Running`
  sleep 30s
done


#
# show node public ip
#
echo -e "\n${LTPURPLE}Get public IP for jupyterhub${NC}"
kubectl get service --namespace $NAMESPACE

# get IP for k8s master
#
echo -e "\n${LTPURPLE}Get k8s master IP for pyspark${NC}"
kubectl cluster-info

# create service account for spark
#
echo -e "\n${LTPURPLE}Setup spark service account${NC}"
kubectl create serviceaccount spark --namespace=$NAMESPACE
kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=$NAMESPACE:spark --namespace=$NAMESPACE

# create service account for spark
#
echo -e "\n${LTPURPLE}Setup spark driver service ${NC}"
kubectl create --namespace $NAMESPACE -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jhub-sparkdriver
  labels:
    app: jhub-sparkdriver
spec:
  clusterIP: None
  type: ClusterIP
  ports:
    - port: 4040 # <-- spark UI
  selector:
    app: jhub-sparkdriver
EOF

# create privs for dashaboard
#
echo -e "\n${LTPURPLE}Setup dasboard privieges${NC}"
kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
