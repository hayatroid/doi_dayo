# doi_dayo

DOI を管理する traQ bot だよ

![](https://github.com/user-attachments/assets/574c9bef-b345-400d-8c13-2f97b2c1f9c7)

## コマンド

| コマンド                     | 動作                                           |
| ---------------------------- | ---------------------------------------------- |
| `@BOT_doi_dayo add <doi>...` | doi.org からタイトル・出版年を取得して登録する |
| `@BOT_doi_dayo ls`           | このチャンネルの一覧を表で出す                 |
| `@BOT_doi_dayo rm <id>`      | `ls` に出る `#id` を削除する                   |

上記以外の入力にはヘルプを返す。リストはチャンネル (DM 含む) 単位である。

## ローカル開発 (Elixir 1.20 / OTP 28)

```sh
docker compose up -d                     # MariaDB (root / doi_dayo)
mix deps.get && mix ecto.setup
mix test
BOT_ACCESS_TOKEN=... mix run --no-halt   # 実 traQ に接続する場合
```

## 環境変数

| 変数                                                | 説明                                                  |
| --------------------------------------------------- | ----------------------------------------------------- |
| `BOT_ACCESS_TOKEN`                                  | traQ bot のトークン。未設定のとき WS 接続を起動しない |
| `NS_MARIADB_{USER,PASSWORD,HOSTNAME,PORT,DATABASE}` | DB 接続情報。デフォルトは compose の値                |
