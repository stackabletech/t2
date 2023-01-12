FROM debian:10

# create T2 workspace directory
RUN mkdir -p /var/t2/workspace/

# install helpful tools
RUN apt-get update
RUN apt-get install curl python3 python3-pip unzip wget vim git gcc pkg-config jq openjdk-11-jdk gnupg uuid -y

# install Terraform
RUN wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.2.3/terraform_1.2.3_linux_amd64.zip
RUN mkdir /tmp/terraform/
RUN unzip /tmp/terraform.zip -d /tmp/terraform/
RUN install -o root -g root -m 0755 /tmp/terraform/terraform /usr/local/bin/terraform
RUN rm /tmp/terraform.zip
RUN rm -rf /tmp/terraform/

# install kubectl
RUN wget -O /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
RUN rm /tmp/kubectl

# install Helm and the Stackable Helm repos
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -
RUN helm repo add stackable-dev https://repo.stackable.tech/repository/helm-dev/
RUN helm repo add stackable-stable https://repo.stackable.tech/repository/helm-stable/
RUN helm repo add stackable-test https://repo.stackable.tech/repository/helm-test/
RUN helm repo update

# install AWS CLI
RUN mkdir /tmp/awscli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" > /tmp/awscli/awscliv2.zip
RUN unzip /tmp/awscli/awscliv2.zip -d /tmp/awscli/
RUN /tmp/awscli/aws/install

# install eksctl (from AWS)
RUN curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
RUN install -o root -g root -m 0755 /tmp/eksctl /usr/local/bin/eksctl

# install yq (YAML Parser)
RUN wget https://github.com/mikefarah/yq/releases/download/v4.25.1/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq

# install wireguard
RUN sh -c "echo 'deb http://deb.debian.org/debian buster-backports main contrib non-free' > /etc/apt/sources.list.d/buster-backports.list"
RUN apt update
RUN apt install wireguard -y

# install Ansible
RUN pip3 install ansible

# install python packages 
RUN pip3 install netaddr ipaddress PyYAML

# install GCloud CLI
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg  add - && apt-get update -y && apt-get install google-cloud-cli google-cloud-sdk-gke-gcloud-auth-plugin -y
ENV USE_GKE_GCLOUD_AUTH_PLUGIN "True"

# add template directory
ADD templates/ /var/t2/templates/

# add SpringBoot executable JAR
ARG JAR_FILE
ADD target/${JAR_FILE} /var/t2/t2-server.jar

# add T2 start script
COPY t2.sh /
RUN chmod 755 /t2.sh

ARG T2_DISPLAY_VERSION=
ENV T2_DISPLAY_VERSION=${T2_DISPLAY_VERSION}
ENTRYPOINT ["/t2.sh"]



