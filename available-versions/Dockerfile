FROM centos:8

# install helm
RUN yum install curl -y
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -
RUN helm repo add stackable-dev https://repo.stackable.tech/repository/helm-dev/
RUN helm repo add stackable-test https://repo.stackable.tech/repository/helm-test/
RUN helm repo add stackable-stable https://repo.stackable.tech/repository/helm-stable/

COPY cmd.sh /cmd.sh

CMD [ "bash", "/cmd.sh" ]





