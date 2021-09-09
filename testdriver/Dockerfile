FROM python:3

RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
RUN echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
RUN apt-get install -y kubectl
RUN apt-get install -y gcc libssl-dev pkg-config
RUN apt-get install -y git

RUN curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

COPY python_modules /
RUN pip install --no-cache-dir -r python_modules

COPY testdriver.py /

ENV KUBECONFIG /root/.kube/config
ENV PATH "/root/.cargo/bin:$PATH"
RUN mkdir -p /root/.kube/

CMD [ "python", "/testdriver.py" ]





