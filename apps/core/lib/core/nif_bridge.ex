defmodule Core.NifBridge do
  @moduledoc """
  Rustler NIF — **`run_formula_bytecode/3` のみ**（`Core.Formula` 経由で利用）。

  ゲーム ECS・物理用 NIF はフェーズ 4 で Rust 側から削除済み。

  **XR / VR 入力**は NIF を経由しない。クライアント側 `native/xr`・`network` 経由で
  Zenoh 等に乗り、サーバでは `Contents.Events.Game` へメッセージとして届く。
  `config :core, Core.NifBridge, features: ["xr"]` は歴史的な mix フックの残りで、
  現行 `native/nif` に XR 専用コードは無い。
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
