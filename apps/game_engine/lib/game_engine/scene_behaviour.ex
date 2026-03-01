defmodule GameEngine.SceneBehaviour do
  @moduledoc """
  シーンコールバックの動作定義。

  各シーンは init/1, update/2, render_type/0 を実装する。
  SceneManager がスタックで管理し、GameEvents が update を呼び出す。
  """

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
