# calmana
+ 動作環境
  + ruby 2.5.5
  + bundle 2.1.4

+ 説明
  + Google Calendar APIのWatchを利用した，Google Calendar上の変更を監視するシステム

+ 機能
  + 変更が行われた予定のデータを取得・保存
  + 過去の変更履歴からユーザの操作を推測
  + heron との連携による年間カレンダの生成

## Setup
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
  $ bundle exec ruby calmana.rb
  ```
  この際，Google Calendar API の credentials.json が必要になる．
  + [Google API console](https://console.developers.google.com)
  
  認証に成功すると，`Aouthorize Success!`と表示される．

## Run
+ サーバの起動
  ```
  bundle exec ruby calmana.rb 
  ```
  
+ Channel の作成
  + コード中に CALLBACK URL を記述（settings.yml など別ファイルから読み込めるように変更予定）

  + 監視するカレンダの calendar id を指定して実行
  ```
  bundle exec ruby channel.rb make <calendar ID>
  ```
  + 現時点では作成可能なチャンネルは一つのみ（需要があるかはともかく，複数のカレンダを監視できるようにしたい）
  
+ 変更された予定の情報は `result/` 以下に保存(ディレクトリ名おかしいから要改名)

+ チャンネルの削除
  + 監視するカレンダの calendar id を指定して実行
  ```
  bundle exec ruby channel.rb make <calendar ID>
  ```
  
+ heron と連携する場合
  + [heron](https://github.com/nomlab/heron-Rust) の環境構築
  + コンパイルしてバイナリファイルを生成
  ```
  cargo build
  ```
  
### or

+ スクリプトを実行(未実装)
  ```
  sh scripts/launch.sh start
  ```
  
## 今後の予定
+ `settings.yml` から CALLBACK URL など必要な情報の読み込み
+ Channel の複数作成への対応
+ 実行スクリプトの作成

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
    ```
    <VirtualHost *:443>
            ServerName <Domain name>
    
            SSLEngine on
            SSLProxyEngine on
    
            ProxyPass / <Application URL>
            ProxyPassReverse / <Application URL>
    
            SSLCertificateFile /etc/letsencrypt/live/<Domain name>/fullchain.pem
            SSLCertificateKeyFile /etc/letsencrypt/live/<Domain name>/privkey.pem
    
            ErrorLog ${APACHE_LOG_DIR}/calmana_error.log
            CustomLog ${APACHE_LOG_DIR}/calmana_access.log combined
    </VirtualHost>
    ```

  + Apache の設定を再読込
