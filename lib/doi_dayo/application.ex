defmodule DoiDayo.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :doi_dayo,
    adapter: Ecto.Adapters.MyXQL
end

defmodule DoiDayo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        DoiDayo.Repo,
        {Task.Supervisor, name: DoiDayo.TaskSupervisor}
      ] ++ traq_child()

    Supervisor.start_link(children, strategy: :one_for_one, name: DoiDayo.Supervisor)
  end

  # BOT_ACCESS_TOKEN が無いとき、WS 接続を起動しない。
  defp traq_child do
    case Application.get_env(:doi_dayo, :bot, [])[:access_token] do
      nil -> []
      token -> [{DoiDayo.Traq, token: token, task_supervisor: DoiDayo.TaskSupervisor}]
    end
  end
end
