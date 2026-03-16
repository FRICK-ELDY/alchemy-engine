defmodule Contents.Scenes do
  @moduledoc """
  シーン呼び出しのファサード。

  Content はシーンモジュールを直接呼ばず、本モジュールの `init/1` / `update/2` / `render_type/1` を経由する。
  「どのシーンか」の定義は Scenes は持たず、呼び出し元が init_arg に `%{module: mod, payload: payload}` を渡す。

  ## 契約とエラー

  - `init/1`: init_arg は**必ず** `%{module: mod, payload: payload}` であること。nil やキー欠損・型違いでは FunctionClauseError。
  - `update/2`: state は**必ず** `%{scene_module: mod, inner_state: inner}`（本ファサードの init 返り）であること。ファサード未使用の Content が誤って渡した場合も FunctionClauseError。
  - `mod` は `Contents.SceneBehaviour` を実装していること。実装漏れは `mod.init(payload)` / `mod.update/2` 実行時に検知される（事前チェックは行っていない）。
  """

  @doc """
  シーンを初期化する。

  init_arg は**必ず** `%{module: mod, payload: payload}` の形であること。
  mod の `init(payload)` を呼び、返りが `{:ok, state}` のとき
  `{:ok, %{scene_module: mod, inner_state: state}}` を返す。
  """
  def init(%{module: mod, payload: payload}) do
    case mod.init(payload) do
      {:ok, state} ->
        {:ok, %{scene_module: mod, inner_state: state}}

      other ->
        other
    end
  end

  @doc """
  現在シーンの描画種別を返す。

  state は `%{scene_module: mod, inner_state: _}` の形であること。
  それ以外では FunctionClauseError。
  """
  def render_type(%{scene_module: mod, inner_state: _}) do
    mod.render_type()
  end

  @doc """
  シーンを更新する。

  state は `%{scene_module: mod, inner_state: inner}` の形であること（本ファサードの init 返り）。
  mod の `update(context, inner)` を呼び、返り値の state 部分を同様に包んで返す。
  契約外の state では FunctionClauseError。
  """
  def update(context, %{scene_module: mod, inner_state: inner}) do
    result = mod.update(context, inner)
    wrap_transition_result(result, mod)
  end

  # Contents.Behaviour.Scenes の 8 パターンのみ処理。それ以外（将来拡張や typo）は意図的に FunctionClauseError で失敗させる。
  defp wrap_transition_result({:continue, new_inner}, mod) do
    {:continue, %{scene_module: mod, inner_state: new_inner}}
  end

  defp wrap_transition_result({:continue, new_inner, opts}, mod) do
    {:continue, %{scene_module: mod, inner_state: new_inner}, opts}
  end

  defp wrap_transition_result({:transition, :pop, new_inner}, mod) do
    {:transition, :pop, %{scene_module: mod, inner_state: new_inner}}
  end

  defp wrap_transition_result({:transition, :pop, new_inner, opts}, mod) do
    {:transition, :pop, %{scene_module: mod, inner_state: new_inner}, opts}
  end

  defp wrap_transition_result({:transition, {:push, _m, _a} = action, new_inner}, mod) do
    {:transition, action, %{scene_module: mod, inner_state: new_inner}}
  end

  defp wrap_transition_result({:transition, {:push, _m, _a} = action, new_inner, opts}, mod) do
    {:transition, action, %{scene_module: mod, inner_state: new_inner}, opts}
  end

  defp wrap_transition_result({:transition, {:replace, _m, _a} = action, new_inner}, mod) do
    {:transition, action, %{scene_module: mod, inner_state: new_inner}}
  end

  defp wrap_transition_result({:transition, {:replace, _m, _a} = action, new_inner, opts}, mod) do
    {:transition, action, %{scene_module: mod, inner_state: new_inner}, opts}
  end
end
