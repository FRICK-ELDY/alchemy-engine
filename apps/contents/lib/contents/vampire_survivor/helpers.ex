defmodule Content.VampireSurvivor.Helpers do
  @moduledoc """
  VampireSurvivor コンテンツ配下のコンポーネントで共有するヘルパー関数。

  Content のオプショナルコールバック（accumulate_exp/2, apply_boss_defeated/1 等）を
  function_exported? でガードして呼び出す処理を集約し、重複を避ける。
  """

  @doc """
  content が accumulate_exp/2 を実装していれば呼び出し、そうでなければ state をそのまま返す。
  """
  def maybe_accumulate_exp(state, content, exp) do
    if function_exported?(content, :accumulate_exp, 2),
      do: content.accumulate_exp(state, exp),
      else: state
  end

  @doc """
  content が apply_boss_defeated/1 を実装していれば呼び出し、そうでなければ state をそのまま返す。
  """
  def maybe_apply_boss_defeated(state, content) do
    if function_exported?(content, :apply_boss_defeated, 1),
      do: content.apply_boss_defeated(state),
      else: state
  end
end
