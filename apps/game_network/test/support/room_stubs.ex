defmodule GameNetwork.Test.StubRoom do
  @moduledoc """
  テスト用の軽量ルームプロセス。

  本番の NIF / Rust ゲームループは起動せず、
  受信した `{:network_event, from, event}` メッセージを蓄積する。
  自身を `GameEngine.RoomRegistry` に登録するため、
  `GameNetwork.Local` からのイベント配信が正常に動作する。

  ## 起動方法

  `start_supervised` には `room_id` 単体、または `{room_id, opts}` タプルを渡す。

      start_supervised({StubRoom, "room_a"})
      start_supervised({StubRoom, {"room_b", notify: self()}})

  ## 受信通知

  `notify: pid` オプションを渡すと、ネットワークイベントを受信するたびに
  `{:stub_room_received, room_id, from, event}` を指定プロセスに送信する。
  テストで `assert_receive` による同期確認が可能になる。
  """

  use GenServer

  @doc """
  ルームを起動する。

  - `room_id` — `String.t() | atom()`（opts なし）
  - `{room_id, opts}` — `opts` は `notify: pid` を受け付けるキーワードリスト
  """
  def start_link({room_id, opts}) when is_list(opts) do
    GenServer.start_link(__MODULE__, {room_id, opts})
  end

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, {room_id, []})
  end

  @doc false
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary,
    }
  end

  @doc "受信したネットワークイベント一覧を返す（受信順）。"
  def received_events(pid) do
    GenServer.call(pid, :received_events)
  end

  @impl true
  def init({room_id, opts}) do
    GameEngine.RoomRegistry.register(room_id)
    notify = Keyword.get(opts, :notify)
    {:ok, %{room_id: room_id, events: [], notify: notify}}
  end

  @impl true
  def handle_call(:received_events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  @impl true
  def handle_info({:network_event, from, event}, state) do
    if state.notify do
      send(state.notify, {:stub_room_received, state.room_id, from, event})
    end

    {:noreply, %{state | events: [{from, event} | state.events]}}
  end

  def handle_info({:move_input, dx, dy}, state) do
    if state.notify do
      send(state.notify, {:move_input_received, dx, dy})
    end

    {:noreply, state}
  end

  def handle_info({:ui_action, name}, state) do
    if state.notify do
      send(state.notify, {:ui_action_received, name})
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
