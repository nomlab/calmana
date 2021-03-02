#calmana
+ 動作環境
  + ruby 2.5.5
  + bundle 2.1.4

+ 説明
  + Google Calendar APIのWatchを利用した，Google Calendar上の変更を監視するシステム

# Setup
+ Clone code
  ```
  $ git clone git@github.com:nakazono0424/calmana.git
  ```

+ Install gems
  ```
  $ bundle install --path vendor/bundle
  ```

+ aouthorize
  ```
  $ bundle exec ruby channel.rb
  ```
  この際，Google Calendar API の credentials.json が必要になる．
  + [Google API console](https://console.developers.google.com)
  
  認証に成功すると，`Aouthorize Success!`と表示される．

# HTTPS の設定
+ 前提
  このプログラムはリバースプロキシで遷移したローカルサーバ上で動作する．

+ リバースプロキシサーバで行う設定
  + Certbot のインストール
    ```
    $ sudo apt-get install certbot
    ```

  + Certbot を実行
    ```
    $ sudo certbot certonly --webroot -d <ドメイン名> --agree-tos
    ```
    証明書の取得に成功すると，証明書のファイルが`/etc/letsencrypt/live/<ドメイン名>/`以下に生成される
    
  + Apache の設定を編集
    + fib

  + Apache の設定を再読込
    + fib