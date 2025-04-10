FROM mozillabteam/bmo-perl-slim:20240822.1 AS base

ENV DEBIAN_FRONTEND=noninteractive

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_URL

ENV CI=${CI}
ENV CIRCLE_BUILD_URL=${CIRCLE_BUILD_URL}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

# we run a loopback logging server on this TCP port.
ENV LOG4PERL_CONFIG_FILE=log4perl-json.conf
ENV LOGGING_PORT=5880
ENV LOCALCONFIG_ENV=1

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y rsync curl \
    && rm -rf /var/lib/apt/lists/*

# Add cloudflare gpg key
RUN mkdir -p --mode=0755 /usr/share/keyrings \
  && curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null 

# Add this repo to your apt repositories
RUN echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main" | tee /etc/apt/sources.list.d/cloudflared.list

# install cloudflared
RUN apt-get update && apt-get install cloudflared lsof sudo
RUN adduser app sudo
RUN echo 'app ALL=NOPASSWD: ALL' >> /etc/sudoers

# install sendmail
RUN apt install -y sendmail
RUN echo Y | sudo sendmailconfig

WORKDIR /app

COPY . /app

RUN chown -R app:app /app && \
    perl -I/app -I/app/local/lib/perl5 -c -E 'use Bugzilla; BEGIN { Bugzilla->extensions }' && \
    perl -c /app/scripts/entrypoint.pl

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE 8000

HEALTHCHECK CMD curl -sfk http://localhost -o/dev/null

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]

FROM base AS test

HEALTHCHECK NONE

USER root

RUN apt-get update \
    && apt-get install -y firefox-esr lsof \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L https://github.com/mozilla/geckodriver/releases/download/v0.33.0/geckodriver-v0.33.0-linux64.tar.gz -o /tmp/geckodriver.tar.gz \
  && cd /tmp \
  && tar zxvf geckodriver.tar.gz \
  && mv geckodriver /usr/bin/geckodriver
# Add cloudflare gpg key
RUN mkdir -p --mode=0755 /usr/share/keyrings \
  && curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null \

# Add this repo to your apt repositories
RUN echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# install cloudflared
RUN apt-get update && sudo apt-get install cloudflared
# install sendmail
RUN apt install -y sendmail
RUN echo Y | sudo sendmailconfig
USER app
