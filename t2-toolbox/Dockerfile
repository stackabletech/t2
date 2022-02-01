FROM debian:10

# install helpful tools
RUN apt-get update
RUN apt-get install curl python3 unzip wget vim git gcc libssl-dev pkg-config -y

# install Helm and the Stackable Helm repos
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -
RUN helm repo add stackable-dev https://repo.stackable.tech/repository/helm-dev/
RUN helm repo add stackable-stable https://repo.stackable.tech/repository/helm-stable/
RUN helm repo update

# install Azure command line tool
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# install kubectl
RUN wget -O /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
RUN rm /tmp/kubectl

# install k9s
RUN wget -O /tmp/k9s.tar.gz https://github.com/derailed/k9s/releases/download/v0.25.18/k9s_Linux_x86_64.tar.gz
RUN mkdir /tmp/k9s/
RUN tar -xzf /tmp/k9s.tar.gz  -C /tmp/k9s/
RUN install -o root -g root -m 0755 /tmp/k9s/k9s /usr/local/bin/k9s
RUN rm /tmp/k9s.tar.gz
RUN rm -rf /tmp/k9s/

# install Terraform
RUN wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.1.4/terraform_1.1.4_linux_amd64.zip
RUN mkdir /tmp/terraform/
RUN unzip /tmp/terraform.zip -d /tmp/terraform/
RUN install -o root -g root -m 0755 /tmp/terraform/terraform /usr/local/bin/terraform
RUN rm /tmp/terraform.zip
RUN rm -rf /tmp/terraform/

# install Rust
RUN curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH "/root/.cargo/bin:$PATH"