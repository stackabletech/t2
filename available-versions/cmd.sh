yum list available --showduplicates 2> /dev/null | grep 'stackable-agent.x86_64' | sed 's/.x86_64//' | sed 's/.el8//' | awk '{print $1"/"$2}'
yum list available --showduplicates 2> /dev/null | grep 'stackable' | grep 'operator' | sed 's/.x86_64//' | sed 's/.el8//' | awk '{print $1"/"$2}'
