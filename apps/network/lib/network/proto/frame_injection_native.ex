# FrameInjection ネイティブ protobuf（proto/frame_injection.proto と対応）
defmodule Network.Proto.FrameInjection do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :player_input, 1, proto3_optional: true, type: Network.Proto.Vec2f
  field :player_snapshot, 2, proto3_optional: true, type: Network.Proto.Vec2f
  field :elapsed_seconds, 3, proto3_optional: true, type: :double
  field :weapon_slots, 4, proto3_optional: true, type: Network.Proto.WeaponSlotsList
  field :enemy_damage_this_frame, 5, proto3_optional: true, type: Network.Proto.EnemyDamageList
  field :special_entity_snapshot, 6, proto3_optional: true, type: Network.Proto.SpecialEntitySnapshot
end

defmodule Network.Proto.Vec2f do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
end

defmodule Network.Proto.WeaponSlotsList do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :slots, 1, repeated: true, type: Network.Proto.WeaponSlot
end

defmodule Network.Proto.WeaponSlot do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :kind_id, 1, type: :uint32
  field :level, 2, type: :uint32
  field :cooldown, 3, type: :float
  field :cooldown_sec, 4, type: :float
  field :precomputed_damage, 5, type: :int32
end

defmodule Network.Proto.EnemyDamageList do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :pairs, 1, repeated: true, type: Network.Proto.EnemyDamagePair
end

defmodule Network.Proto.EnemyDamagePair do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :kind_id, 1, type: :uint32
  field :damage, 2, type: :float
end

defmodule Network.Proto.SpecialEntitySnapshot do
  @moduledoc false
  use Protobuf, syntax: :proto3

  oneof :state, 0

  field :none, 1, type: Network.Proto.SpecialNone, oneof: 0
  field :alive, 2, type: Network.Proto.SpecialAlive, oneof: 0
end

defmodule Network.Proto.SpecialNone do
  @moduledoc false
  use Protobuf, syntax: :proto3
end

defmodule Network.Proto.SpecialAlive do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :radius, 3, type: :float
  field :damage, 4, type: :float
  field :invincible, 5, type: :bool
end
