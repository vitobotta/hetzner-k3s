FROM ruby:2.7.4-alpine

RUN apk update --no-cache \
  && apk add build-base git openssh-client

COPY Gemfile Gemfile
COPY hetzner-k3s.gemspec hetzner-k3s.gemspec

RUN gem install hetzner-k3s

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

