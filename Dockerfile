FROM ruby:3.1.4-bullseye

# 必要なパッケージをインストール
RUN apt-get update -qq && apt-get install -y \
    nodejs \
    build-essential \
    libsqlite3-dev

# 作業ディレクトリを設定
WORKDIR /usr/src/redmine

# Gemfile と Gemfile.lock をコピー
COPY Gemfile Gemfile.lock ./

# Bundler をインストール
RUN gem install bundler

# アプリケーションのソースコードをコピー
COPY . .

# Gem をインストール
RUN bundle install

# ポートを公開
EXPOSE 3000

# サーバーを起動するコマンドを設定
CMD ["rails", "server", "-b", "0.0.0.0"]