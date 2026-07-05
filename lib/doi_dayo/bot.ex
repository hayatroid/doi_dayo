defmodule DoiDayo.Bot do
  @moduledoc """
  メンション・DM イベントからコマンドをパース・実行し、traQ に返信する。
  DOI の正規化 (downcase) は境界である `parse/1` で 1 回だけ行い、以降の層では正規化済みとして扱う。
  """

  alias DoiDayo.Papers
  alias DoiDayo.Papers.Paper
  alias DoiDayo.Traq

  @handled_types ~w(MESSAGE_CREATED DIRECT_MESSAGE_CREATED)

  # 本文中の埋め込み JSON `!{...}` は位置によらず除去する。
  @mention_embed ~r/!\{[^}]*\}/
  @doi_regex ~r/^10\.\d{4,9}\/\S+$/

  @type command :: {:add, [String.t()]} | :ls | {:rm, pos_integer()} | :help

  @help """
  使い方だよ：
  ```sh
  @BOT_doi_dayo add <doi>...   DOI を登録する (例: add 10.1136/bmj.331.7531.1498)
  @BOT_doi_dayo ls             このチャンネルの一覧を出す
  @BOT_doi_dayo rm <id>        #id を消す
  ```
  """

  # --- イベント処理 ---

  @doc "envelope map を受け取ったとき、対象イベントならコマンドを処理し、それ以外は無視する。"
  @spec handle(map()) :: :ok
  def handle(%{
        "type" => type,
        "body" => %{
          "message" => %{
            "text" => text,
            "channelId" => channel_id,
            "user" => %{"id" => user_id}
          }
        }
      })
      when type in @handled_types do
    # bot 自身の投稿は traQ がイベント配信しない (filterBotUserIDNotEquals)。
    text
    |> strip_mention()
    |> parse()
    |> run(channel_id, user_id)
  end

  def handle(_event), do: :ok

  # --- コマンドパース (純関数) ---

  @doc "コマンド文字列を受け取ったとき、コマンドをパースして返す。パース不能なら `:help` を返す。"
  @spec parse(String.t()) :: command()
  def parse(text) do
    case text |> String.trim() |> String.split() do
      ["add" | args] -> parse_add(args)
      ["ls" | _rest] -> :ls
      ["rm", id] -> parse_rm(id)
      _other -> :help
    end
  end

  # --- 返信文整形 (純関数) ---

  @spec help() :: String.t()
  def help, do: String.trim_trailing(@help)

  @spec added(Paper.t()) :: String.t()
  def added(%Paper{} = paper), do: "登録したよ：##{paper.id} #{title(paper)}"

  @spec add_failed(String.t()) :: String.t()
  def add_failed(doi), do: "#{doi} は見つからなかったよ。DOI あってる？"

  @spec duplicate(String.t()) :: String.t()
  def duplicate(doi), do: "それはもう登録されてるよ：#{doi}"

  @doc "論文一覧を受け取ったとき、Markdown テーブルを返す。空なら未登録である旨を返す。"
  @spec list([Paper.t()]) :: String.t()
  def list([]), do: "まだ何も登録されてないよ"

  def list(papers) do
    "| # | タイトル | 年 | DOI |\n| --- | --- | --- | --- |\n" <>
      Enum.map_join(papers, "\n", &row/1)
  end

  @spec removed(pos_integer()) :: String.t()
  def removed(id), do: "##{id} を消したよ"

  @spec not_found(pos_integer()) :: String.t()
  def not_found(id), do: "##{id} は見つからなかったよ"

  # --- private ---

  defp strip_mention(text) do
    text
    |> String.replace(@mention_embed, "")
    |> String.trim()
  end

  defp parse_add(args) do
    case args |> Enum.filter(&doi?/1) |> Enum.map(&String.downcase/1) |> Enum.uniq() do
      [] -> :help
      dois -> {:add, dois}
    end
  end

  defp parse_rm(id) do
    case Integer.parse(id) do
      {n, ""} when n > 0 -> {:rm, n}
      _other -> :help
    end
  end

  defp doi?(token), do: Regex.match?(@doi_regex, token)

  defp run({:add, dois}, channel_id, user_id) do
    reply = Enum.map_join(dois, "\n", &add_one(&1, channel_id, user_id))
    Traq.post_message(channel_id, reply)
  end

  defp run(:ls, channel_id, _user_id) do
    Traq.post_message(channel_id, list(Papers.list(channel_id)))
  end

  defp run({:rm, id}, channel_id, _user_id) do
    reply =
      case Papers.delete(channel_id, id) do
        :ok -> removed(id)
        {:error, :not_found} -> not_found(id)
      end

    Traq.post_message(channel_id, reply)
  end

  defp run(:help, channel_id, _user_id) do
    Traq.post_message(channel_id, help())
  end

  defp add_one(doi, channel_id, user_id) do
    case Papers.get(channel_id, doi) do
      %Paper{} ->
        duplicate(doi)

      nil ->
        case Papers.register(channel_id, doi, user_id) do
          {:ok, paper} -> added(paper)
          {:error, %Ecto.Changeset{}} -> duplicate(doi)
          {:error, :metadata} -> add_failed(doi)
        end
    end
  end

  defp row(%Paper{} = paper) do
    "| #{paper.id} | #{title(paper)} | #{paper.year} | [#{paper.doi}](//doi.org/#{paper.doi}) |"
  end

  defp title(%Paper{} = paper), do: paper.title || "(タイトル不明)"
end
