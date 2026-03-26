defmodule Contents.Behaviour.Scenes do
  @moduledoc """
  Scene 層の Behaviour。時間軸としての契約。

  ## 責務

  - **時間の区切り**: いまどの段階か、次にどこへ遷移するか。
  - **origin（空間の原点）**: Scene がシーン座標系の基準（Transform）を持つ。新規・将来コンテンツでは state に持つことを推奨。
  - **着地点参照（任意）**: ユーザーが Scene に降り立つ際のフォーカス対象となる Object への参照（例: `landing_object`）。必須ではなく、必要に応じて state に持つ。root_object 必須は廃止。
  - **遷移管理**: init/update/render_type により SceneStack と連携。

  参照: docs/architecture/scene-and-object.md, workspace/2_todo/scene-origin-and-landing-reference-plan.md
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @doc """
      Scene を初期化する。

      返却する state には、新規・将来コンテンツでは **origin**（空間の原点）を持ち、
      必要に応じて **着地点参照**（例: `landing_object`）を含めることを推奨する。
      root_object 必須は廃止。既存コンテンツは root_object を残したままでも許容。
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
    end
  end
end
