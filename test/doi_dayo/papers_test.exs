defmodule DoiDayo.PapersTest do
  use ExUnit.Case, async: true

  alias DoiDayo.Papers
  alias DoiDayo.Papers.Paper
  alias DoiDayo.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @channel_a "channel-a"
  @channel_b "channel-b"

  setup tags do
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    Req.Test.verify_on_exit!()
    :ok
  end

  defp insert!(overrides) do
    attrs =
      Map.merge(
        %{channel_id: @channel_a, doi: "10.1136/bmj.331.7531.1498", registered_by: "user-1"},
        overrides
      )

    Repo.insert!(struct!(Paper, attrs))
  end

  defp stub_metadata(csl_json) do
    Req.Test.stub(DoiDayo.Papers, fn conn -> Req.Test.json(conn, csl_json) end)
  end

  describe "register/3" do
    test "doi.org からタイトル・出版年を取得して登録する (ヘッダも検証)" do
      Req.Test.stub(DoiDayo.Papers, fn conn ->
        assert conn.request_path == "/10.1136/bmj.331.7531.1498"

        assert Plug.Conn.get_req_header(conn, "accept") == [
                 "application/vnd.citationstyles.csl+json"
               ]

        assert [ua] = Plug.Conn.get_req_header(conn, "user-agent")
        assert ua =~ "doi_dayo"

        Req.Test.json(conn, %{
          "title" =>
            "The case of the disappearing teaspoons: longitudinal cohort study of the displacement of teaspoons in an Australian research institute",
          "issued" => %{"date-parts" => [[2005, 12, 22]]}
        })
      end)

      assert {:ok, %Paper{} = paper} =
               Papers.register(@channel_a, "10.1136/bmj.331.7531.1498", "user-1")

      assert paper.title =~ "disappearing teaspoons"
      assert paper.year == 2005
      assert paper.registered_by == "user-1"
    end

    test "issued が無い CSL JSON でも year nil で登録できる" do
      stub_metadata(%{"title" => "No Date Paper"})

      assert {:ok, %Paper{title: "No Date Paper", year: nil}} =
               Papers.register(@channel_a, "10.1145/no-date", "user-1")
    end

    test "解決できない DOI (404) は登録せず {:error, :metadata}" do
      Req.Test.stub(DoiDayo.Papers, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:error, :metadata} = Papers.register(@channel_a, "10.1145/nope", "user-1")
      assert Papers.get(@channel_a, "10.1145/nope") == nil
    end

    test "transport error でも {:error, :metadata}" do
      Req.Test.stub(DoiDayo.Papers, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, :metadata} = Papers.register(@channel_a, "10.1145/timeout", "user-1")
    end

    test "同一チャンネルの重複 DOI は changeset エラー" do
      insert!(%{})
      stub_metadata(%{"title" => "Dup"})

      assert {:error, %Ecto.Changeset{}} =
               Papers.register(@channel_a, "10.1136/bmj.331.7531.1498", "user-1")
    end

    test "別チャンネルなら同じ DOI を登録できる" do
      insert!(%{channel_id: @channel_a})
      stub_metadata(%{"title" => "Same DOI, Another Channel"})

      assert {:ok, %Paper{}} = Papers.register(@channel_b, "10.1136/bmj.331.7531.1498", "user-1")
    end
  end

  describe "get/2" do
    test "チャンネル内の登録を返す" do
      paper = insert!(%{})
      assert Papers.get(@channel_a, paper.doi).id == paper.id
    end

    test "他チャンネルの登録は見えない" do
      insert!(%{channel_id: @channel_a})
      assert Papers.get(@channel_b, "10.1136/bmj.331.7531.1498") == nil
    end
  end

  describe "list/1" do
    test "チャンネル内の登録だけを登録順に返す" do
      p1 = insert!(%{doi: "10.1145/aaa"})
      p2 = insert!(%{doi: "10.1145/bbb"})
      insert!(%{channel_id: @channel_b, doi: "10.1145/ccc"})

      assert Papers.list(@channel_a) |> Enum.map(& &1.id) == [p1.id, p2.id]
    end
  end

  describe "delete/2" do
    test "チャンネル内の登録を削除する" do
      paper = insert!(%{})
      assert :ok = Papers.delete(@channel_a, paper.id)
      assert Papers.get(@channel_a, paper.doi) == nil
    end

    test "存在しない id は {:error, :not_found}" do
      assert {:error, :not_found} = Papers.delete(@channel_a, 999_999)
    end

    test "他チャンネルの登録は削除できない (チャンネルスコープ)" do
      paper = insert!(%{channel_id: @channel_a})

      assert {:error, :not_found} = Papers.delete(@channel_b, paper.id)
      assert Papers.get(@channel_a, paper.doi).id == paper.id
    end
  end
end
