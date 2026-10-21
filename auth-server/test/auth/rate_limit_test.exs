defmodule Auth.RateLimitTest do
  use ExUnit.Case, async: false

  alias Auth.RateLimit

  setup do
    RateLimit.reset()
    :ok
  end

  describe "hit/3" do
    test "allows requests up to the configured limit" do
      config = %{limit: 2, period_ms: 60_000}

      assert :ok = RateLimit.hit(:login_ip, "127.0.0.1", config)
      assert :ok = RateLimit.hit(:login_ip, "127.0.0.1", config)
      assert {:error, :rate_limited} = RateLimit.hit(:login_ip, "127.0.0.1", config)
    end

    test "tracks buckets independently" do
      config = %{limit: 1, period_ms: 60_000}

      assert :ok = RateLimit.hit(:login_ip, "127.0.0.1", config)
      assert :ok = RateLimit.hit(:login_identifier, "user@example.com", config)
      assert {:error, :rate_limited} = RateLimit.hit(:login_ip, "127.0.0.1", config)
    end

    test "tracks keys independently within the same bucket" do
      config = %{limit: 1, period_ms: 60_000}

      assert :ok = RateLimit.hit(:login_ip, "10.0.0.1", config)
      assert :ok = RateLimit.hit(:login_ip, "10.0.0.2", config)
      assert {:error, :rate_limited} = RateLimit.hit(:login_ip, "10.0.0.1", config)
    end

    test "emits telemetry when throttled" do
      handler_id = "rate-limit-test-#{System.unique_integer()}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:auth, :rate_limit, :throttle],
          fn event, measurements, metadata, _config ->
            send(self(), {event, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      config = %{limit: 1, period_ms: 60_000}
      assert :ok = RateLimit.hit(:login_ip, "127.0.0.1", config)
      assert {:error, :rate_limited} = RateLimit.hit(:login_ip, "127.0.0.1", config)

      assert_receive {[:auth, :rate_limit, :throttle], %{count: 1},
                      %{action: :login, axis: :ip, bucket: :login_ip}}

      refute_receive {[:auth, :rate_limit, :throttle], _, _}

      assert {:error, :rate_limited} = RateLimit.hit(:login_ip, "127.0.0.1", config)
      refute_receive {[:auth, :rate_limit, :throttle], _, _}
    end

    test "cleanup does not reset long-period buckets" do
      config = %{limit: 2, period_ms: 3_600_000}

      assert :ok = RateLimit.hit(:register_email, "user@example.com", config)
      assert :ok = RateLimit.hit(:register_email, "user@example.com", config)

      send(Auth.RateLimit, :cleanup)

      assert {:error, :rate_limited} =
               RateLimit.hit(:register_email, "user@example.com", config)
    end
  end
end
