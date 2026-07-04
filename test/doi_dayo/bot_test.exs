defmodule DoiDayo.BotTest do
  @moduledoc "コマンドパース・返信文整形の単体テストと、handle/1 の結合テスト (Req.Test + DB sandbox)。"

  use ExUnit.Case

  alias DoiDayo.Bot
  alias DoiDayo.Papers
  alias DoiDayo.Papers.Paper
  alias DoiDayo.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @channel "channel-1"
  @sender "sender-1"

  setup tags do
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    previous = Application.get_env(:doi_dayo, :bot, [])
    Application.put_env(:doi_dayo, :bot, access_token: "dummy")
    on_exit(fn -> Application.put_env(:doi_dayo, :bot, previous) end)

    Req.Test.verify_on_exit!()
    :ok
  end

  describe "parse/1" do
    test "add: 単一 DOI" do
      assert Bot.parse("add 10.1136/bmj.331.7531.1498") == {:add, ["10.1136/bmj.331.7531.1498"]}
    end

    test "add: 複数 DOI・downcase・重複排除" do
      assert Bot.parse("add 10.1145/AAA 10.1145/aaa 10.1145/bbb") ==
               {:add, ["10.1145/aaa", "10.1145/bbb"]}
    end

    test "add: DOI でないトークンは落とす" do
      assert Bot.parse("add not-a-doi 10.1145/aaa") == {:add, ["10.1145/aaa"]}
    end

    test "add: 引数なしは help" do
      assert Bot.parse("add") == :help
    end

    test "ls" do
      assert Bot.parse("ls") == :ls
      assert Bot.parse("ls now") == :ls
    end

    test "rm: 正の整数 id" do
      assert Bot.parse("rm 3") == {:rm, 3}
    end

    test "rm: 不正な id は help" do
      assert Bot.parse("rm abc") == :help
      assert Bot.parse("rm 0") == :help
      assert Bot.parse("rm -1") == :help
      assert Bot.parse("rm") == :help
    end

    test "空文字・未知コマンドは help" do
      assert Bot.parse("") == :help
      assert Bot.parse("   ") == :help
      assert Bot.parse("frobnicate") == :help
    end
  end

  describe "返信文整形" do
    test "help/0 はコードブロックで 3 コマンドすべてに言及する" do
      help = Bot.help()
      assert help =~ "使い方だよ"
      assert help =~ "```"
      assert help =~ "add"
      assert help =~ "ls"
      assert help =~ "rm"
    end

    test "list/1 は Markdown テーブル、DOI はリンク、年 nil は空欄" do
      papers = [
        %Paper{id: 1, doi: "10.1145/aaa", title: "A Great Paper", year: 2019},
        %Paper{id: 2, doi: "10.1145/bbb", title: nil, year: nil}
      ]

      table = Bot.list(papers)
      assert table =~ "| # | タイトル | 年 | DOI |"
      assert table =~ "| 1 | A Great Paper | 2019 | https://doi.org/10.1145/aaa |"
      assert table =~ "| 2 | (タイトル不明) |  | https://doi.org/10.1145/bbb |"
    end

    test "list/1 は空リストで未登録メッセージ" do
      assert Bot.list([]) == "まだ何も登録されてないよ"
    end
  end

  describe "handle/1 (結合)" do
    defp mention(text) do
      %{
        "type" => "MENTION_MESSAGE_CREATED",
        "body" => %{
          "message" => %{
            "channelId" => @channel,
            "user" => %{"id" => @sender},
            "text" => ~s(!{"type":"user","raw":"@BOT_doi_dayo","id":"bot-user-id"} #{text})
          }
        }
      }
    end

    defp insert!(attrs) do
      Repo.insert!(
        struct!(Paper, Map.merge(%{channel_id: @channel, registered_by: @sender}, attrs))
      )
    end

    defp capture_reply do
      test_pid = self()

      Req.Test.stub(DoiDayo.Traq, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:posted, conn.request_path, Jason.decode!(body)["content"]})
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{})
      end)
    end

    defp posted_content do
      assert_received {:posted, path, content}
      assert path == "/api/v3/channels/#{@channel}/messages"
      content
    end

    test "add: メタデータ取得 → DB 登録 → カード返信まで通る" do
      Req.Test.stub(DoiDayo.Papers, fn conn ->
        Req.Test.json(conn, %{
          "title" =>
            "The case of the disappearing teaspoons: longitudinal cohort study of the displacement of teaspoons in an Australian research institute",
          "issued" => %{"date-parts" => [[2005]]}
        })
      end)

      capture_reply()
      assert :ok = Bot.handle(mention("add 10.1136/bmj.331.7531.1498"))

      assert %Paper{
               title: "The case of the disappearing" <> _,
               year: 2005,
               registered_by: @sender
             } =
               Papers.get(@channel, "10.1136/bmj.331.7531.1498")

      content = posted_content()
      assert content =~ "登録したよ"
      assert content =~ "disappearing teaspoons"
    end

    test "add: 登録済み DOI は「登録されてるよ」を返し、メタデータを再取得しない" do
      insert!(%{doi: "10.1136/bmj.331.7531.1498"})

      capture_reply()
      assert :ok = Bot.handle(mention("add 10.1136/bmj.331.7531.1498"))
      assert posted_content() =~ "もう登録されてるよ"
    end

    test "add: 解決できない DOI は登録せずエラー返信" do
      Req.Test.stub(DoiDayo.Papers, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      capture_reply()
      assert :ok = Bot.handle(mention("add 10.1145/nope"))

      assert Papers.get(@channel, "10.1145/nope") == nil
      assert posted_content() =~ "10.1145/nope は見つからなかったよ"
    end

    test "ls: 同一チャンネルの登録だけを返す" do
      insert!(%{doi: "10.1145/aaa", title: "Here"})
      insert!(%{channel_id: "other", doi: "10.1145/bbb", title: "Elsewhere"})

      capture_reply()
      assert :ok = Bot.handle(mention("ls"))

      content = posted_content()
      assert content =~ "Here"
      refute content =~ "Elsewhere"
    end

    test "rm: id 指定で削除できる" do
      paper = insert!(%{doi: "10.1145/aaa"})

      capture_reply()
      assert :ok = Bot.handle(mention("rm #{paper.id}"))

      assert posted_content() =~ "を消したよ"
      assert Papers.get(@channel, "10.1145/aaa") == nil
    end

    test "対象外イベントは無視する" do
      assert :ok = Bot.handle(%{"type" => "PING", "body" => %{}})
    end
  end
end
