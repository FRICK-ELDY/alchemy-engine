defmodule Core.NifBridge do
  @moduledoc """
  Rustler NIF — **`run_formula_bytecode/3` のみ**（`Core.Formula` 経由で利用）。

  ゲーム ECS・物理用 NIF はフェーズ 4 で Rust 側から削除済み。

  VR 用に `config :core, Core.NifBridge, features: ["xr"]` を付けても、
  現行 `native/nif` クレートに xr 専用コードは無い（将来用フック）。
  """

  use Rustler,
    otp_app: :core,
    crate: :nif,
    path: "../../native/nif"

  @doc """
  bytecode: バイナリ形式のバイトコード
  inputs: %{"name" => value}
  store_values: Store 初期値 %{"key" => value}
  """
  def run_formula_bytecode(_bytecode, _inputs, _store_values),
    do: :erlang.nif_error(:nif_not_loaded)
end
