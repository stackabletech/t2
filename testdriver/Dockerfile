FROM python:3

# install OS tools
RUN apt-get update
RUN apt-get install -y gcc libssl-dev pkg-config colorized-logs unzip wget vim git

# install kubectl
RUN wget -O /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
RUN rm /tmp/kubectl

# install Helm and the Stackable Helm repos
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -
RUN helm repo add stackable-dev https://repo.stackable.tech/repository/helm-dev/
RUN helm repo add stackable-stable https://repo.stackable.tech/repository/helm-stable/
RUN helm repo update

# install k9s
RUN wget -O /tmp/k9s.tar.gz https://github.com/derailed/k9s/releases/download/v0.25.18/k9s_Linux_x86_64.tar.gz
RUN mkdir /tmp/k9s/
RUN tar -xzf /tmp/k9s.tar.gz  -C /tmp/k9s/
RUN install -o root -g root -m 0755 /tmp/k9s/k9s /usr/local/bin/k9s
RUN rm /tmp/k9s.tar.gz
RUN rm -rf /tmp/k9s/

# install Docker
# (https://docs.docker.com/engine/install/debian/)
RUN apt-get update
RUN apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt-get update
RUN apt-get install -y docker-ce docker-ce-cli containerd.io

# install Rust
RUN curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# install required Python modules
COPY python_modules /
RUN pip install --no-cache-dir -r python_modules

# set kubeconfig location
ENV KUBECONFIG /root/.kube/config

# add cargo (Rust) to path
ENV PATH "/root/.cargo/bin:$PATH"

# create user folders
RUN mkdir -p /root/.kube/
RUN mkdir -p /root/.ssh/

# install logs to retrieve operator logs
COPY operator-logs.sh /
RUN chmod a+x /operator-logs.sh

# install kubectl-kuttl
RUN wget -O /tmp/kubectl-kuttl https://github.com/kudobuilder/kuttl/releases/download/v0.11.1/kubectl-kuttl_0.11.1_linux_x86_64
RUN install -o root -g root -m 0755 /tmp/kubectl-kuttl /usr/local/bin/kubectl-kuttl
RUN rm /tmp/kubectl-kuttl

# Testdriver script
COPY testdriver.py /

CMD [ "python", "/testdriver.py" ]
