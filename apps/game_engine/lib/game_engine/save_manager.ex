defmodule GameEngine.SaveManager do
  require Logger

  @session_path "saves/session.dat"
  @high_scores_path "saves/high_scores.dat"
  @high_scores_max 10

  def save_session(world_ref) do
    try do
      snapshot = GameEngine.NifBridge.get_save_snapshot(world_ref)
      binary = :erlang.term_to_binary(snapshot)
      File.mkdir_p!("saves")
      File.write!(@session_path, binary)
      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def load_session(world_ref) do
    case File.read(@session_path) do
      {:ok, binary} ->
        try do
          snapshot = :erlang.binary_to_term(binary)
          snapshot = Map.put_new(snapshot, :kill_count, 0)
          GameEngine.NifBridge.load_save_snapshot(world_ref, snapshot)
          :ok
        rescue
          e -> {:error, Exception.message(e)}
        end

      {:error, :enoent} ->
        :no_save

      {:error, reason} ->
        {:error, :file.format_error(reason)}
    end
  end

  def has_save? do
    File.exists?(@session_path)
  end

  def save_high_score(score) when is_integer(score) and score >= 0 do
    try do
      current = load_high_scores()
      new_list = [score | current] |> Enum.uniq() |> Enum.sort(:desc) |> Enum.take(@high_scores_max)
      File.mkdir_p!("saves")
      File.write!(@high_scores_path, :erlang.term_to_binary(new_list))
      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def save_high_score(_), do: {:error, :invalid_score}

  def load_high_scores do
    case File.read(@high_scores_path) do
      {:ok, binary} ->
        try do
          :erlang.binary_to_term(binary)
        rescue
          e ->
            Logger.warning("Failed to deserialize high scores: #{Exception.message(e)}")
            []
        end

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("Failed to read high scores file: #{:file.format_error(reason)}")
        []
    end
  end

  def best_score do
    case load_high_scores() do
      [best | _] -> best
      [] -> nil
    end
  end
end
