FROM python:3

# install OS tools
RUN apt-get update
RUN apt-get install -y gcc libssl-dev pkg-config colorized-logs unzip wget vim git gettext curl jq

# install required Python modules
COPY python_modules /
RUN pip install --no-cache-dir -r python_modules

# install ansible
RUN apt-get update
RUN apt-get install -y ansible

# Reporting script and required files
COPY reporting.py /

CMD [ "python", "/reporting.py" ]
