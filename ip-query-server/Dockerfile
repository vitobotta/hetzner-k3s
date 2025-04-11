FROM ruby:3.4.2

WORKDIR /app

COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock

RUN bundle install

COPY . /app
EXPOSE 4567

CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "4567"]
