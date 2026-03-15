defmodule Contents.Scenes.Core.Behaviour do
  @moduledoc """
  Scene 層の Behaviour。時間軸としての契約。

  ## 責務

  - **時間の区切り**: いまどの段階か、次にどこへ遷移するか。
  - **root_object（必須）**: Object ツリーのルート参照。ユーザーが Scene に降り立つ着地点。
    どの Object をルートにするかはコンテンツ製作者が選択。新規・将来コンテンツでは state に
    `%{root_object: Object.t(), ...}` を持つことを必須とする。
  - **遷移管理**: init/update/render_type により SceneStack と連携。

  参照: docs/architecture/scene-and-object.md
  """

  @doc """
  Scene を初期化する。

  返却する state には `root_object` を**必須**で含める（新規・将来コンテンツ）。
  root_object はユーザーが Scene に降り立つ着地点となる Object。
  """
  @callback init(init_arg :: term()) :: {:ok, state :: term()}

  @doc """
  フレームごとに呼ばれる。遷移の場合は `{:transition, ...}` を返す。
  """
  @callback update(context :: map(), state :: term()) ::
              {:continue, state :: term()}
              | {:continue, state :: term(), opts :: map()}
              | {:transition, :pop, state :: term()}
              | {:transition, :pop, state :: term(), opts :: map()}
              | {:transition, {:push, module(), init_arg :: term()}, state :: term()}
              | {:transition, {:push, module(), init_arg :: term()}, state :: term(),
                 opts :: map()}
              | {:transition, {:replace, module(), init_arg :: term()}, state :: term()}
              | {:transition, {:replace, module(), init_arg :: term()}, state :: term(),
                 opts :: map()}

  @doc """
  描画種別を返す（例: :playing, :title）。
  """
  @callback render_type() :: atom()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @callback init(init_arg :: term()) :: {:ok, state :: term()}

      @callback update(context :: map(), state :: term()) ::
                  {:continue, state :: term()}
                  | {:continue, state :: term(), opts :: map()}
                  | {:transition, :pop, state :: term()}
                  | {:transition, :pop, state :: term(), opts :: map()}
                  | {:transition, {:push, module(), init_arg :: term()}, state :: term()}
                  | {:transition, {:push, module(), init_arg :: term()}, state :: term(),
                     opts :: map()}
                  | {:transition, {:replace, module(), init_arg :: term()}, state :: term()}
                  | {:transition, {:replace, module(), init_arg :: term()}, state :: term(),
                     opts :: map()}

      @callback render_type() :: atom()
    end
  end
end
