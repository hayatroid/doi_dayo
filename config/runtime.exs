import Config

database_name = System.get_env("NS_MARIADB_DATABASE", "doi_dayo")
# test のとき、dev と別 DB を使う。
database = if config_env() == :test, do: database_name <> "_test", else: database_name

config :doi_dayo, DoiDayo.Repo,
  username: System.get_env("NS_MARIADB_USER", "root"),
  password: System.get_env("NS_MARIADB_PASSWORD", "doi_dayo"),
  hostname: System.get_env("NS_MARIADB_HOSTNAME", "localhost"),
  port: String.to_integer(System.get_env("NS_MARIADB_PORT", "3306")),
  database: database

if config_env() == :test do
  # test のとき、DB 接続は Ecto.Adapters.SQL.Sandbox 経由でテストごとにロールバックする。
  config :doi_dayo, DoiDayo.Repo, pool: Ecto.Adapters.SQL.Sandbox, log: false

  # test のとき、HTTP 呼び出しは Req.Test の stub に差し替える。
  config :doi_dayo, :metadata_req_options, plug: {Req.Test, DoiDayo.Papers}
  config :doi_dayo, :api_req_options, plug: {Req.Test, DoiDayo.Traq}
end

config :doi_dayo, :bot, access_token: System.get_env("BOT_ACCESS_TOKEN")
