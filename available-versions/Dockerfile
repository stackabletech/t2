FROM centos:8

COPY stackable-releases.repo /etc/yum.repos.d/stackable-releases.repo
COPY stackable-dev.repo /etc/yum.repos.d/stackable-dev.repo

COPY cmd.sh /cmd.sh

CMD [ "bash", "/cmd.sh" ]





