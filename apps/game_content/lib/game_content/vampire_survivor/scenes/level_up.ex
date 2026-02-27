defmodule GameContent.VampireSurvivor.Scenes.LevelUp do
  @moduledoc """
  レベルアップ武器選択シーン。物理演算を一時停止。
  """
  @behaviour GameEngine.SceneBehaviour

  @level_up_auto_select_ms 3_000

  @impl GameEngine.SceneBehaviour
  def init(%{choices: choices, entered_ms: entered_ms} = init_arg) do
    level = Map.get(init_arg, :level)
    {:ok, %{choices: choices, entered_ms: entered_ms, level: level}}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :level_up

  @impl GameEngine.SceneBehaviour
  def update(_context, %{entered_ms: entered_ms} = state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - entered_ms

    if elapsed >= @level_up_auto_select_ms do
      {:transition, :pop, Map.put(state, :auto_select, true)}
    else
      {:continue, state}
    end
  end
end
