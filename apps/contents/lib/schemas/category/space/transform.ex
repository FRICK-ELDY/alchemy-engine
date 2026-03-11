defmodule Schemas.Category.Space.Transform do
  @moduledoc """
  変換型。位置・回転・スケールを表す。

  回転は内部では Quaternion で保持し、編集者は Euler（ラジアン、Blender XYZ 準拠）で操作する。
  `from_euler_rad/2` / `to_euler_rad/1` で変換する。

  ## 構造

      %{
        position: Value.Float.t3(),    # 位置 (x, y, z)
        rotation: Value.Float.quaternion(),  # 回転 (x, y, z, w)
        scale: Value.Float.t3()        # スケール (x, y, z)
      }

  ## Blender Euler 仕様

  - 順序: XYZ（Extrinsic、固定軸）
  - 単位: ラジアン
  """
  alias Schemas.Category.Value.Float, as: ValueFloat

  @type t :: %{
          required(:position) => ValueFloat.t3(),
          required(:rotation) => ValueFloat.quaternion(),
          required(:scale) => ValueFloat.t3()
        }

  @type euler_rad :: ValueFloat.t3()
  @euler_singularity_threshold 0.4999

  @doc """
  デフォルトの Transform を生成する。

  位置・回転はゼロ/単位、スケールは (1, 1, 1)。
  """
  @spec new() :: t()
  def new do
    %{
      position: {0.0, 0.0, 0.0},
      rotation: {0.0, 0.0, 0.0, 1.0},
      scale: {1.0, 1.0, 1.0}
    }
  end

  @doc """
  編集者が Euler（ラジアン、Blender XYZ）で指定した回転を適用して Transform を返す。

  `euler_rad` は `{x, y, z}` のタプル。ラジアン単位。Blender の `rotation_euler` と互換。

  ## 例

      transform = Transform.new()
      Transform.put_rotation_euler_rad(transform, {0.0, :math.pi() / 4, 0.0})
  """
  @spec put_rotation_euler_rad(t(), euler_rad()) :: t()
  def put_rotation_euler_rad(transform, euler_rad) do
    quat = euler_xyz_to_quaternion(elem(euler_rad, 0), elem(euler_rad, 1), elem(euler_rad, 2))
    %{transform | rotation: quat}
  end

  @doc """
  `put_rotation_euler_rad/2` の別名。Euler（ラジアン）から回転を設定する。
  """
  @spec from_euler_rad(t(), euler_rad()) :: t()
  defdelegate from_euler_rad(transform, euler_rad), to: __MODULE__, as: :put_rotation_euler_rad

  @doc """
  内部の Quaternion を Euler（ラジアン、Blender XYZ）に変換して編集者へ返す。

  ## 例

      {x, y, z} = Transform.to_euler_rad(transform)
  """
  @spec to_euler_rad(t()) :: euler_rad()
  def to_euler_rad(%{rotation: quat}), do: quaternion_to_euler_xyz(quat)

  # Euler XYZ (extrinsic, radians) → Quaternion
  # Blender eul_to_mat3 の行列 R = Rz(z) * Ry(y) * Rx(x) から導出
  defp euler_xyz_to_quaternion(x, y, z) do
    sx = :math.sin(x / 2)
    cx = :math.cos(x / 2)
    sy = :math.sin(y / 2)
    cy = :math.cos(y / 2)
    sz = :math.sin(z / 2)
    cz = :math.cos(z / 2)

    # q = qz * qy * qx
    # qx = (sx, 0, 0, cx), qy = (0, sy, 0, cy), qz = (0, 0, sz, cz)
    qx = {sx, 0.0, 0.0, cx}
    qy = {0.0, sy, 0.0, cy}
    qz = {0.0, 0.0, sz, cz}
    qyx = quat_mul(qy, qx)
    quat_mul(qz, qyx)
  end

  # Quaternion → Euler XYZ (extrinsic, radians)
  # Blender 互換。ジンバルロック時は heading に集約して bank=0 とする
  defp quaternion_to_euler_xyz({qx, qy, qz, qw}) do
    test = qx * qy + qz * qw
    sqx = qx * qx
    sqy = qy * qy
    sqz = qz * qz
    sqw = qw * qw
    unit = sqx + sqy + sqz + sqw

    # euclideanspace: heading=Y軸, attitude=Z軸, bank=X軸
    # Blender XYZ = (X, Y, Z) = (bank, heading, attitude)
    cond do
      test > @euler_singularity_threshold * unit ->
        # 北極（ジンバルロック）。heading に集約、bank=0
        heading = 2 * :math.atan2(qx, qw)
        {0.0, heading, :math.pi() / 2}

      test < -@euler_singularity_threshold * unit ->
        # 南極（ジンバルロック）
        heading = -2 * :math.atan2(qx, qw)
        {0.0, heading, -:math.pi() / 2}

      true ->
        bank = :math.atan2(2 * qx * qw - 2 * qy * qz, -sqx + sqy - sqz + sqw)
        heading = :math.atan2(2 * qy * qw - 2 * qx * qz, sqx - sqy - sqz + sqw)
        attitude = :math.asin(2 * test / unit)
        {bank, heading, attitude}
    end
  end

  defp quat_mul({x1, y1, z1, w1}, {x2, y2, z2, w2}) do
    x = w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2
    y = w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2
    z = w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2
    w = w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2
    {x, y, z, w}
  end
end
