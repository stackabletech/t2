FROM adoptopenjdk/openjdk11:alpine

RUN mkdir -p /var/t2/workspace/

# install curl
RUN apk add curl

# install openssl
RUN apk add openssl

# install Terraform 
RUN wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.1.0/terraform_1.1.0_linux_amd64.zip
RUN unzip /tmp/terraform.zip -d /tmp/
RUN mv /tmp/terraform /usr/bin/

# install kubectl
RUN wget -O /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN install -o root -g root -m 0755 /tmp/kubectl /usr/bin/kubectl
RUN rm /tmp/kubectl

# install Helm and the Stackable Helm repos
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sh -s -
RUN helm repo add stackable-dev https://repo.stackable.tech/repository/helm-dev/
RUN helm repo add stackable-stable https://repo.stackable.tech/repository/helm-stable/
RUN helm repo add stackable-test https://repo.stackable.tech/repository/helm-test/

# install Python
RUN apk add python3
RUN apk add py3-pip
RUN pip install netaddr
RUN pip install ipaddress

# install Ansible
RUN apk add ansible

# install Wireguard Tools to generate key
RUN apk add wireguard-tools

# install ssh
RUN apk add openssh

# install git
RUN apk add git

# add template directory
ADD templates/ /var/t2/templates/

# add SpringBoot executable JAR
ARG JAR_FILE
ADD target/${JAR_FILE} /var/t2/t2-server.jar

ENTRYPOINT ["java", "-Djava.security.egd=file:/dev/./urandom", "-Dspring.profiles.active=docker", "-jar", "/var/t2/t2-server.jar"]


