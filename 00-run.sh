#!/bin/bash
# git clone https://gitee.com/qingcaihub/nextcloud-onlyoffice
# cd nextcloud-onlyoffice
for i in {01..11} ; do kubectl apply -f $i* ; done
sleep 200
kubectl exec -it -n nextcloud nextcloud-app-0 -- /bin/bash /tmp/run.sh

