defmodule Alchemy.Frame.FrameInjectionEnvelope do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.FrameInjectionEnvelope",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:payload, 1, type: :bytes)
end

defmodule Alchemy.Frame.FrameInjection do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.FrameInjection",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:player_input, 1,
    proto3_optional: true,
    type: Alchemy.Frame.Vec2f,
    json_name: "playerInput"
  )

  field(:player_snapshot, 2,
    proto3_optional: true,
    type: Alchemy.Frame.Vec2f,
    json_name: "playerSnapshot"
  )

  field(:elapsed_seconds, 3, proto3_optional: true, type: :double, json_name: "elapsedSeconds")

  field(:weapon_slots, 4,
    proto3_optional: true,
    type: Alchemy.Frame.WeaponSlotsList,
    json_name: "weaponSlots"
  )

  field(:enemy_damage_this_frame, 5,
    proto3_optional: true,
    type: Alchemy.Frame.EnemyDamageList,
    json_name: "enemyDamageThisFrame"
  )

  field(:special_entity_snapshot, 6,
    proto3_optional: true,
    type: Alchemy.Frame.SpecialEntitySnapshot,
    json_name: "specialEntitySnapshot"
  )
end

defmodule Alchemy.Frame.Vec2f do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.Vec2f",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:x, 1, type: :float)
  field(:y, 2, type: :float)
end

defmodule Alchemy.Frame.WeaponSlotsList do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.WeaponSlotsList",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:slots, 1, repeated: true, type: Alchemy.Frame.WeaponSlot)
end

defmodule Alchemy.Frame.WeaponSlot do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.WeaponSlot",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:kind_id, 1, type: :uint32, json_name: "kindId")
  field(:level, 2, type: :uint32)
  field(:cooldown, 3, type: :float)
  field(:cooldown_sec, 4, type: :float, json_name: "cooldownSec")
  field(:precomputed_damage, 5, type: :int32, json_name: "precomputedDamage")
end

defmodule Alchemy.Frame.EnemyDamageList do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.EnemyDamageList",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:pairs, 1, repeated: true, type: Alchemy.Frame.EnemyDamagePair)
end

defmodule Alchemy.Frame.EnemyDamagePair do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.EnemyDamagePair",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:kind_id, 1, type: :uint32, json_name: "kindId")
  field(:damage, 2, type: :float)
end

defmodule Alchemy.Frame.SpecialEntitySnapshot do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.SpecialEntitySnapshot",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:state, 0)

  field(:none, 1, type: Alchemy.Frame.SpecialNone, oneof: 0)
  field(:alive, 2, type: Alchemy.Frame.SpecialAlive, oneof: 0)
end

defmodule Alchemy.Frame.SpecialNone do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.SpecialNone",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Alchemy.Frame.SpecialAlive do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.frame.SpecialAlive",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:x, 1, type: :float)
  field(:y, 2, type: :float)
  field(:radius, 3, type: :float)
  field(:damage, 4, type: :float)
  field(:invincible, 5, type: :bool)
end
