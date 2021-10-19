FROM adoptopenjdk/openjdk11:alpine

RUN mkdir -p /var/t2/workspace/

# install Terraform 
RUN wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.0.9/terraform_1.0.9_linux_amd64.zip
RUN unzip /tmp/terraform.zip -d /tmp/
RUN mv /tmp/terraform /usr/bin/

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

# add template directory
ADD templates/ /var/t2/templates/

# add SpringBoot executable JAR
ARG JAR_FILE
ADD target/${JAR_FILE} /var/t2/t2-server.jar

ENTRYPOINT ["java", "-Djava.security.egd=file:/dev/./urandom", "-Dspring.profiles.active=docker", "-jar", "/var/t2/t2-server.jar"]


