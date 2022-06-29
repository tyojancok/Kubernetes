declare UI_POD_NAME;
declare BUS_POD_NAME;
declare DB_POD_NAME;
declare ProductsUIClusterIP;
declare ProductBusinessClusterIP;
declare ProductsDBClusterIP;
declare POD_BUSINESS_STAGE_NS;
declare POD_UI_STAGE_;

function setup_env(){
    cleanup

    kubectl create namespace products-prod
    kubectl create namespace products-stage

    #Deploy PODS to Products-prod name space
    kubectl create deployment products-ui -n products-prod --image=gcr.io/google-samples/hello-app:1.0
    kubectl create deployment products-business -n products-prod --image=gcr.io/google-samples/hello-app:1.0
    kubectl create deployment products-db -n products-prod --image=gcr.io/google-samples/hello-app:1.0

    #Create service for our deployment
    kubectl expose deployment products-ui -n products-prod --port=8080 --target-port=8080 --type=NodePort
    kubectl expose deployment products-business -n products-prod --port=8080 --target-port=8080 --type=NodePort
    kubectl expose deployment products-db -n products-prod --port=8080 --target-port=8080 --type=NodePort

    #Deploy PODS to Products-stage name space
    kubectl create deployment products-ui --image=gcr.io/google-samples/hello-app:1.0 -n products-stage
    kubectl create deployment products-business --image=gcr.io/google-samples/hello-app:1.0 -n products-stage

    #get POD names for the UI, Business, and Database tiers (products-prod name space)
    kubectl get pods -n products-prod
    UI_POD_NAME=$(kubectl get pods -n products-prod | awk ' NR>1 {print $1}' | grep products-ui)
    BUS_POD_NAME=$(kubectl get pods -n products-prod | awk ' NR>1 {print $1}' | grep products-business)
    DB_POD_NAME=$(kubectl get pods -n products-prod | awk ' NR>1 {print $1}' | grep products-db)

    #get POD names for the UI, and Business tiers (products-stage name space)
    BUS_POD_NAME_STAGE=$(kubectl get pods -n products-stage | awk ' NR>1 {print $1}' | grep products-business)
    UI_POD_NAME_STAGE=$(kubectl get pods -n products-stage | awk ' NR>1 {print $1}' | grep products-ui)

    #get the cluster IPs
    kubectl get service -o wide -n products-prod
    #get products UI ClusterIP
    ProductsUIClusterIP=$(kubectl get service products-ui -n products-prod -o jsonpasth='{.spec.clusterIP}')
    ProductBusinessClusterIP=$(kubectl get service products-business -n products-prod -o jsonpasth='{.spec.clusterIP}')
    ProductsDBClusterIP=$(kubectl get service products-db -n products-prod -o jsonpasth='{.spec.clusterIP}')
}

setup_env

#test from services on varios tiers from node
curl --max-time 1.5 http://$ProductsUIClusterIP:8080
curl --max-time 1.5 http://$ProductBusinessClusterIP:8080
curl --max-time 1.5 http://$ProductsDBClusterIP:8080

#test from services on varios tiers from inside PODs
kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductBusinessClusterIP:8080 -O -
kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
kubectl exec -it $BUS_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

kubectl exec -it $UI_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductBusinessClusterIP:8080 -O -
kubectl exec -it $UI_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
kubectl exec -it $BUS_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductBusinessClusterIP:8080 -O -
kubectl exec -it $BUS_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

#apply network policy to restric ingres access Bussiness and DB pods

    kubectl apply -f restric-access-to-ui-tier-only.yaml -n products-prod

    kubectl apply -f restric-access-to-business-tier-only.yaml -n products-prod

    #test again
    kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductBusinessClusterIP:8080 -O -
    kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
    kubectl exec -it $BUS_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

    kubectl exec -it $UI_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductBusinessClusterIP:8080 -O -
    kubectl exec -it $UI_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
    kubectl exec -it $BUS_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductBusinessClusterIP:8080 -O -
    kubectl exec -it $BUS_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

#apply network policy to allow stage Bussiness pod aaccess db pods in prod
    #label stage namespace
    kubectl label namespace products-stage products-prod-db-access=allow

    #apply the policy
    kubectl apply -f allow-business-tier-access-to-db.yaml
    
    #retest
    kubectl exec -it $UI_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
    kubectl exec -it $BUS_POD_NAME_STAGE -n products-prod --wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

#check if DB pod has egress access to outside cluster
 kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://10.0.0.24:8080/computer -O -

 #restric egress "db" pod traffic to pod network
    kubectl apply -f restric-db-egress-traffic-to-cluster-only.yaml
    #retest
    kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://10.0.0.24:8080/computer -O -
    kubectl exec -it $UI_POD_NAME -n products-prod --nslookup google.com
    kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://google.com -O -
    kubectl exec -it $UI_POD_NAME -n products-prod --wget -q --timeout=2 http://$ProductsUIClusterIP:8080 -O -