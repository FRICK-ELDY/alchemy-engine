defmodule Content.SampleOsc.Playing do
  @moduledoc """
  OSC Sample playing scene.

  Receives LittleOSC floats (0.0 / 1.0) on UDP 10000 for `/1/push1`..`/1/push4`
  and maps each path to a colored box height.
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Components.Category.Network.Osc.Receiver
  alias Contents.Components.Category.Network.Osc.Value
  alias Contents.Components.Category.Procedural.Meshes.Box
  alias Contents.Components.Category.Shader.Skybox
  alias Contents.Objects.Core.CreateEmptyChild
  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Structs.Category.Space.Transform

  @default_port 10_000

  @push_specs [
    %{id: 1, path: "/1/push1", x: -6.0, color: {0.15, 0.40, 0.95, 1.0}},
    %{id: 2, path: "/1/push2", x: -4.0, color: {0.95, 0.85, 0.12, 1.0}},
    %{id: 3, path: "/1/push3", x: 4.0, color: {0.90, 0.18, 0.16, 1.0}},
    %{id: 4, path: "/1/push4", x: 6.0, color: {0.18, 0.78, 0.28, 1.0}}
  ]

  @render_camera_eye {0.0, 3.0, 10.0}
  @render_camera_target {0.0, 0.0, 0.0}
  @render_camera_up {0.0, 1.0, 0.0}
  @render_camera_fov 60.0
  @render_camera_near 0.1
  @render_camera_far 200.0
  @render_color_sky_top {0.12, 0.18, 0.28, 1.0}
  @render_color_sky_bottom {0.35, 0.45, 0.55, 1.0}
  @render_grid_size 20.0
  @render_grid_divisions 20
  @render_color_grid {0.25, 0.28, 0.32, 1.0}
  @render_color_text {0.9, 0.95, 1.0, 1.0}
  @render_color_muted {0.65, 0.72, 0.82, 1.0}
  @render_color_ok {0.2, 0.8, 0.45, 1.0}
  @render_color_error {0.9, 0.35, 0.35, 1.0}
  @render_color_bg {0.05, 0.08, 0.12, 0.92}

  @type state :: %{
          required(:origin) => Transform.t(),
          required(:landing_object) => term(),
          required(:children) => [term()],
          required(:receiver) => pid(),
          required(:push_values) => %{pos_integer() => pid()},
          required(:receiver_port) => integer(),
          required(:local_ips) => [String.t()],
          required(:last_pushes) => %{pos_integer() => term()},
          required(:last_packet) => map() | nil,
          required(:receiver_listening) => boolean(),
          required(:listen_error) => term() | nil,
          required(:hud_visible) => boolean(),
          required(:cursor_grab_request) => :no_change | term()
        }

  @doc "Build one frame. Rendering.Render calls this via Content.build_frame."
  @spec build_frame(state(), term()) :: {list(), term(), term()}
  def build_frame(state, context) do
    Contents.Objects.Components.run_components_for_objects(Map.get(state, :children, []), context)

    commands = build_frame_commands(state)
    camera = build_frame_camera()
    ui = build_frame_ui(state, context)
    {commands, camera, ui}
  end

  @impl Contents.SceneBehaviour
  @spec init(term()) :: {:ok, state()}
  def init(_init_arg) do
    origin = Transform.new()

    top_object =
      ObjectStruct.new(name: "User", components: [Contents.Objects.Components.Noop])

    {:ok, _child} = CreateEmptyChild.create(top_object, name: "Child")

    {:ok, receiver} =
      Receiver.start_link(port: @default_port, access_reason: "LittleOSC Receiver")

    receiver_fields = Receiver.fields(receiver)

    push_values =
      Map.new(@push_specs, fn spec ->
        {:ok, pid} =
          Value.start_link(handler: receiver, path: spec.path, argument_index: 0, value: 0.0)

        {spec.id, pid}
      end)

    last_pushes = Map.new(@push_specs, fn spec -> {spec.id, 0.0} end)

    {:ok,
     %{
       origin: origin,
       landing_object: top_object,
       children: [top_object],
       receiver: receiver,
       push_values: push_values,
       receiver_port: receiver_fields.port,
       local_ips: local_ipv4s(),
       last_pushes: last_pushes,
       last_packet: nil,
       receiver_listening: receiver_fields.is_listening,
       listen_error: Receiver.listen_error(receiver),
       hud_visible: true,
       cursor_grab_request: :no_change
     }}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  @spec update(term(), state()) :: {:continue, state()}
  def update(_context, state) do
    last_pushes =
      Map.new(state.push_values, fn {id, pid} -> {id, Value.get(pid)} end)

    {:continue,
     %{
       state
       | last_pushes: last_pushes,
         last_packet: Receiver.last_packet(state.receiver),
         receiver_listening: Receiver.fields(state.receiver).is_listening,
         listen_error: Receiver.listen_error(state.receiver)
     }}
  end

  defp build_frame_commands(state) do
    grid_vertices =
      Contents.Components.Category.Procedural.Meshes.Grid.grid_plane(
        size: @render_grid_size,
        divisions: @render_grid_divisions,
        color: @render_color_grid
      )[:vertices]

    boxes =
      Enum.map(@push_specs, fn spec ->
        half_h = 0.4 + to_float(Map.get(state.last_pushes, spec.id, 0.0)) * 1.2
        Box.box_3d_command(spec.x, half_h, 3.0, 0.5, half_h, 0.5, spec.color)
      end)

    [
      Skybox.skybox_command(@render_color_sky_top, @render_color_sky_bottom),
      {:grid_plane_verts, grid_vertices}
    ] ++
      boxes
  end

  defp build_frame_camera do
    {:camera_3d, @render_camera_eye, @render_camera_target, @render_camera_up,
     {@render_camera_fov, @render_camera_near, @render_camera_far}}
  end

  defp build_frame_ui(state, context) do
    hud_nodes =
      if Map.get(state, :hud_visible, true) do
        [build_hud_panel(state, context)]
      else
        []
      end

    {:canvas, hud_nodes}
  end

  defp build_hud_panel(state, context) do
    fps_text =
      if context.tick_ms > 0,
        do: "FPS: #{round(1000.0 / context.tick_ms)}",
        else: "FPS: --"

    listen_color = if state.receiver_listening, do: @render_color_ok, else: @render_color_error

    listen_text =
      if state.receiver_listening do
        "Receiver: listening UDP 0.0.0.0:#{state.receiver_port}"
      else
        "Receiver: not listening (#{inspect(state.listen_error)})"
      end

    host_text =
      case state.local_ips do
        [] -> "LittleOSC Host: (no LAN IP found)"
        ips -> "LittleOSC Host: #{Enum.join(ips, "  /  ")}"
      end

    value_lines =
      Enum.map(@push_specs, fn spec ->
        val = format_value(Map.get(state.last_pushes, spec.id, 0.0))

        {:node, {:top_left, {0.0, 0.0}, :wrap},
         {:text, "#{spec.path}  => #{val}", spec.color, 16.0, true}, []}
      end)

    {:node, {:center, {0.0, 0.0}, :wrap}, {:rect, @render_color_bg, 12.0, :none},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 8.0, {24.0, 20.0, 24.0, 20.0}},
        [
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, "OSC Receive (LittleOSC)", @render_color_text, 24.0, true}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, "UDP #{state.receiver_port}  /  /1/push1-4  float 0.0 or 1.0",
            @render_color_muted, 14.0, false}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, listen_text, listen_color, 16.0, true},
           []},
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, host_text, @render_color_text, 16.0, true}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, "Port: #{state.receiver_port}", @render_color_text, 16.0, true}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, fps_text, @render_color_muted, 14.0, false}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []}
        ] ++
          value_lines ++
          [
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "last packet: #{format_last_packet(state.last_packet)}", @render_color_ok,
              14.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text,
              "Set LittleOSC Host to the LAN IP above. 127.0.0.1 will not work from iPhone.",
              @render_color_muted, 13.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "Allow inbound UDP #{state.receiver_port} in Windows Firewall.",
              @render_color_muted, 13.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text,
              "blue=/1/push1  yellow=/1/push2  red=/1/push3  green=/1/push4. ESC toggles HUD.",
              @render_color_muted, 13.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 120.0, 36.0}, []}
          ]}
     ]}
  end

  defp format_last_packet(nil), do: "(none)"

  defp format_last_packet(%{invalid: true, byte_size: size, from: from}) do
    "INVALID #{size} bytes from #{format_from(from)}"
  end

  defp format_last_packet(%{path: path, args: args, from: from}) do
    "#{path} #{inspect(args)} from #{format_from(from)}"
  end

  defp format_last_packet(other), do: inspect(other)

  defp format_from({{a, b, c, d}, port}), do: "#{a}.#{b}.#{c}.#{d}:#{port}"
  defp format_from({ip, port}), do: "#{inspect(ip)}:#{port}"

  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(_), do: 0.0

  defp local_ipv4s do
    case :inet.getifaddrs() do
      {:ok, ifs} ->
        ifs
        |> Enum.flat_map(fn {_name, opts} ->
          case Keyword.get(opts, :addr) do
            {a, b, c, d} when a != 127 and not (a == 169 and b == 254) ->
              ["#{a}.#{b}.#{c}.#{d}"]

            _ ->
              []
          end
        end)
        |> Enum.uniq()

      _ ->
        []
    end
  end
end
