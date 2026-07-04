defmodule DoiDayo.Traq do
  @moduledoc "traQ との接点: WebSocket 接続 (WebSockex) と REST でのメッセージ投稿。"

  use WebSockex

  require Logger

  @ws_url "wss://q.trap.jp/api/v3/bots/ws"
  @base_url "https://q.trap.jp/api/v3"
  @max_backoff_ms 60_000

  defmodule State do
    @moduledoc false
    defstruct [:task_supervisor, attempts: 0]
  end

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    token = Keyword.fetch!(opts, :token)
    task_supervisor = Keyword.fetch!(opts, :task_supervisor)

    WebSockex.start_link(@ws_url, __MODULE__, %State{task_supervisor: task_supervisor},
      name: __MODULE__,
      extra_headers: [{"authorization", "Bearer " <> token}],
      async: true
    )
  end

  @doc "channel_id と本文を受け取ったとき、traQ にメッセージを投稿する。失敗は crash に任せる。"
  @spec post_message(String.t(), String.t()) :: :ok
  def post_message(channel_id, content) do
    opts =
      [
        method: :post,
        url: @base_url <> "/channels/#{channel_id}/messages",
        auth: {:bearer, Application.get_env(:doi_dayo, :bot, [])[:access_token]},
        retry: false,
        json: %{content: content, embed: false}
      ]
      |> Keyword.merge(Application.get_env(:doi_dayo, :api_req_options, []))

    {:ok, %Req.Response{status: 201}} = Req.request(opts)
    :ok
  end

  @impl true
  def handle_connect(_conn, state), do: {:ok, %{state | attempts: 0}}

  @impl true
  def handle_frame({:text, payload}, state) do
    dispatch(payload, state)
    {:ok, state}
  end

  def handle_frame(_frame, state), do: {:ok, state}

  # 切断されたとき、min(2^n 秒, 60 秒) 待って再接続する。
  @impl true
  def handle_disconnect(%{reason: reason}, %State{attempts: attempts} = state) do
    delay = min(1000 * Integer.pow(2, attempts), @max_backoff_ms)
    Logger.warning("[DoiDayo.Traq] disconnected (#{inspect(reason)}), retrying in #{delay}ms")
    Process.sleep(delay)
    {:reconnect, %{state | attempts: attempts + 1}}
  end

  defp dispatch(payload, %State{task_supervisor: task_supervisor}) do
    case Jason.decode(payload) do
      {:ok, event} ->
        Task.Supervisor.start_child(task_supervisor, fn -> run(event) end, restart: :temporary)

      {:error, reason} ->
        Logger.warning("[DoiDayo.Traq] decode failed: #{inspect(reason)}")
    end

    :ok
  end

  defp run(event) do
    DoiDayo.Bot.handle(event)
  rescue
    e ->
      Logger.error(
        "[DoiDayo.Traq] handler crashed: #{Exception.format(:error, e, __STACKTRACE__)}"
      )
  end
end
