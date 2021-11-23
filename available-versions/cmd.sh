helm repo update &>/dev/null
helm search repo --versions --devel | grep 'stackable' | awk -F'/' '{print $2}' | sort | awk '{print $1"/"$2}'
