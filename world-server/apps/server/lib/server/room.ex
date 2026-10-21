defmodule Server.Room do
  @moduledoc """
  1 ルームの子プロセス。シーンスタックとイベントループを `rest_for_one` で束ねる。

  スタックを先に起動する。ループの tick は `flow_runner/1` でそのスタックだけを参照する。
  コンテンツはノードで 1 つ（`config :server, :current`）で、スタックはルームごとである。

  ## 保証

  ループが 1 回異常終了したときはシーンスタックを再起動しない。シーン state は残る。
  ループが持っているのは tick のカウンタで、権威状態はスタック側にある。

  ## 保証しない

  スタックプロセス自体が落ちたときは、その state は `initial_scenes/0` から作り直す。
  そのとき後続のループも再起動する。
  ループがデフォルトの intensity（5 秒に 3 回）を超えて落ちると、このスーパーバイザ自体が終了する。
  動的スーパーバイザは新しいルームを起動する。その起動は `initial_scenes/0` からなので、
  そのルームのシーン state は消える。この時点では他ルームはまだ生きている。
  その再起動が動的スーパーバイザの intensity に達すると、動的スーパーバイザごと落ち、戻るのは `:main` だけである。
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    # DynamicSupervisor.which_children/1 は id を返さない。停止は pid で行う。
    # 旧プロセスが落ちきる前はキーが残る。生きていれば起動を失敗させ、MainRoom が待つ。
    register_room_sup!(room_id)

    content = Application.fetch_env!(:server, :current)

    game =
      Application.get_env(:server, :game_events_module) ||
        raise "config :server, :game_events_module is required"

    # スタックが先。ループの再起動はスタックに届かない。
    children = [
      content.scene_stack_spec(room_id),
      {game, [room_id: room_id]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp register_room_sup!(room_id) do
    case Registry.register(Core.RoomRegistry, {:room_sup, room_id}, []) do
      {:ok, _} ->
        :ok

      # 呼び出し元の unregister では他プロセスのキーは消えない。
      # 死にかけの旧 pid でも already_started として返し、MainRoom が再試行する。
      {:error, {:already_registered, pid}} ->
        exit({:already_started, pid})
    end
  end
end
