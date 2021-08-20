FROM ruby:2.7.4-alpine

RUN apk update --no-cache \
  && apk add build-base git openssh-client

COPY . .

RUN gem install hetzner-k3s

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

