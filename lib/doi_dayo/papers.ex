defmodule DoiDayo.Papers.Paper do
  @moduledoc "チャンネル単位の論文 1 件を表す schema。"

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          channel_id: String.t(),
          doi: String.t(),
          title: String.t() | nil,
          year: integer() | nil,
          registered_by: String.t()
        }

  schema "papers" do
    field :channel_id, :string
    field :doi, :string
    field :title, :string
    field :year, :integer
    field :registered_by, :string

    timestamps()
  end

  @fields [:channel_id, :doi, :title, :year, :registered_by]

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(paper, attrs) do
    paper
    |> cast(attrs, @fields)
    # 同時 add の競合はこの制約が守る。
    |> unique_constraint(:doi, name: :papers_channel_id_doi_index)
  end
end

defmodule DoiDayo.Papers do
  @moduledoc "論文カタログ: doi.org からのメタデータ取得と DB アクセス。全操作をチャンネル単位でスコープする。"

  import Ecto.Query

  alias DoiDayo.Papers.Paper
  alias DoiDayo.Repo

  @user_agent "doi_dayo/0.1 (https://github.com/hayatroid/doi_dayo)"
  @accept "application/vnd.citationstyles.csl+json"

  @doc """
  DOI を受け取ったとき、doi.org からメタデータを取得してチャンネルに登録する。
  解決できなければ `{:error, :metadata}`、重複なら `{:error, changeset}` を返す。
  """
  @spec register(String.t(), String.t(), String.t()) ::
          {:ok, Paper.t()} | {:error, :metadata | Ecto.Changeset.t()}
  def register(channel_id, doi, registered_by) do
    case fetch_metadata(doi) do
      {:ok, metadata} ->
        attrs =
          Map.merge(metadata, %{channel_id: channel_id, doi: doi, registered_by: registered_by})

        %Paper{}
        |> Paper.changeset(attrs)
        |> Repo.insert()

      :error ->
        {:error, :metadata}
    end
  end

  @doc "channel_id と DOI を受け取ったとき、そのチャンネルの登録があれば返す。"
  @spec get(String.t(), String.t()) :: Paper.t() | nil
  def get(channel_id, doi) do
    Repo.get_by(Paper, channel_id: channel_id, doi: doi)
  end

  @doc "channel_id を受け取ったとき、そのチャンネルの登録を登録順に返す。"
  @spec list(String.t()) :: [Paper.t()]
  def list(channel_id) do
    Paper
    |> where(channel_id: ^channel_id)
    |> order_by(asc: :id)
    |> Repo.all()
  end

  @doc "channel_id と id を受け取ったとき、そのチャンネルの登録なら削除し、なければ `{:error, :not_found}` を返す。"
  @spec delete(String.t(), integer()) :: :ok | {:error, :not_found}
  def delete(channel_id, id) do
    case Paper |> where(channel_id: ^channel_id, id: ^id) |> Repo.delete_all() do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  # Req は `+json` サブタイプを自動 decode するため body は map で届く (実 doi.org で検証済み)。
  defp fetch_metadata(doi) do
    opts =
      [
        method: :get,
        base_url: "https://doi.org",
        url: "/" <> doi,
        redirect: true,
        retry: false,
        headers: [{"accept", @accept}, {"user-agent", @user_agent}]
      ]
      |> Keyword.merge(Application.get_env(:doi_dayo, :metadata_req_options, []))

    case Req.request(opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %{title: title(body), year: year(body)}}

      _other ->
        :error
    end
  end

  defp title(%{"title" => title}) when is_binary(title), do: title
  defp title(_csl), do: nil

  defp year(%{"issued" => %{"date-parts" => [[year | _] | _]}}) when is_integer(year), do: year
  defp year(_csl), do: nil
end
