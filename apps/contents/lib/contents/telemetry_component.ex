defmodule Contents.TelemetryComponent do
  @moduledoc """
  LocalUserComponent の入力状態を表示用に整形して返すコンポーネント。

  keyboard / mouse（x, y, delta）を LocalUserComponent から取得し、
  `get_input_state/1` で表示用フォーマットとして返す。P5-2 の MessagePack 検証やデバッグに利用する。

  ## 表示フォーマット例

      keyboard: "w a s d shift_left"
      mouse: {x: 320, y: 240, delta: {x: 1.5, y: -0.3}}
  """
  @behaviour Core.Component

  @impl true
  def on_ready(_world_ref), do: :ok

  @impl true
  def on_event(_event, _context), do: :ok

  @impl true
  def on_nif_sync(_context), do: :ok

  @doc """
  room_id に対応する入力状態を取得する。

  LocalUserComponent（または content が指定した local_user_input_module）から
  keys_held, mouse を読み取り、表示用に整形して返す。

  返り値の形式:

      %{
        keyboard: "w a s d shift_left",  # 押下中のキー（空白区切り）
        mouse: %{
          x: 320.0,      # カーソル X（nil は未取得）
          y: 240.0,      # カーソル Y（nil は未取得）
          delta_x: 1.5,  # 直近のマウス移動量 X
          delta_y: -0.3  # 直近のマウス移動量 Y
        }
      }
  """
  def get_input_state(room_id \\ :main) do
    mod = Contents.ComponentList.local_user_input_module()

    keys_str =
      mod.get_keys_held(room_id)
      |> MapSet.to_list()
      |> Enum.map(&to_string/1)
      |> Enum.sort()
      |> Enum.join(" ")

    mouse = mod.get_mouse(room_id)

    %{
      keyboard: keys_str,
      mouse: mouse
    }
  end
end
