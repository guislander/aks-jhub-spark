# remove az resource groups
#
NAMESPACE=jhub
RESOURCE=jhub
RESOURCEGROUP=myjhub
CLUSTERNAME=myjhub

LTPURPLE='\033[1;35m'
NC='\033[0m'

echo -e "\n${LTPURPLE}Deleting aks jupyterhub helm${NC}"
helm delete $RESOURCE --namespace $NAMESPACE

echo -e "\n${LTPURPLE}Deleting aks jupyterhub namespace${NC}"
kubectl delete namespace $NAMESPACE

echo -e "\n${LTPURPLE}Deleting az jupyterhub aks resource group${NC}"
az group delete --name $RESOURCEGROUP --yes

echo -e "\n${LTPURPLE}Deleting az jupyterhub directory${NC}"
rm -R $CLUSTERNAME

#
# comment out if useing k8s for other than jupyterhub
#
rm -R .kube
