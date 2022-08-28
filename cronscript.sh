#! /bin/bash
pod=$(kubectl get pods --selector=tier=frontend | awk  'NR==2{print $1}')
num1="5000"
cpu=$(kubectl exec -it $pod -- cat /proc/cpuinfo | grep "cpu MHz" | awk  'NR==1{print $4}')
if awk "BEGIN {exit !($cpu < $num1)}"; then
    kubectl scale deployment wordpress --replicas=0
fi
