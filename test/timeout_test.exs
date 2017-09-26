defmodule TimeoutTest do
  use ExUnit.Case, async: true
  doctest Timeout

  describe "new.1" do
    test "builds a Timeout" do
      assert %Timeout{
        base: 100,
        timeout: 100,
        backoff: 1.25,
        backoff_round: 0,
        backoff_max: 1_000,
        random: {1.1, 0.9}
      } = Timeout.new(100, backoff: 1.25, backoff_max: 1_000, random: 0.1)
    end

    test "raises ArgumentError for invalid :random" do
      assert_raise ArgumentError, fn -> Timeout.new(100, random: 2) end
      assert_raise ArgumentError, fn -> Timeout.new(100, random: 0) end
    end
  end

  describe ".reset/1" do
    test "resets the timeout" do
      timeout =
        Timeout.new(100, backoff: 1.25)
        |> Timeout.next()
        |> Timeout.next()
        |> Timeout.next()
        |> Timeout.reset()

      assert %{timeout: 100, backoff_round: 0} = timeout
    end
  end

  describe ".next/1 (without :backoff)" do
    test "returns a static timeout" do
      timeout = Timeout.new(100) |> Timeout.next()
      assert %{timeout: 100} = timeout
      timeout = Timeout.next(timeout)
      assert %{timeout: 100} = timeout
    end
  end

  describe ".next/1 (with :backoff)" do
    setup do
      {:ok, timeout: Timeout.new(100, backoff: 1.25) }
    end

    test "increments the timeout correctly", ctx do
      timeout = Timeout.next(ctx.timeout)
      assert %{timeout: 100} = timeout

      timeout = Timeout.next(timeout)
      assert %{timeout: 125} = timeout

      timeout = Timeout.next(timeout)
      assert %{timeout: 156} = timeout
    end

    test "increments up to a :backoff_max", ctx do
      timeout = %{ctx.timeout | backoff_max: 150}
      timeout = Enum.reduce(1..20, timeout, fn (_, t) -> Timeout.next(t) end)
      assert %{timeout: 150} = timeout
    end
  end

  describe ".current/1" do
    test "returns the configured timeout without :random" do
      assert 100 = Timeout.new(100) |> Timeout.current()
    end

    test "returns the timeout within a range when :random is configured" do
      timeout = Timeout.new(100, random: 0.5)
      assert Timeout.current(timeout) in 51..150
      assert Timeout.current(timeout) in 51..150
    end
  end

  describe ".send_after/3" do
    test "sends a message to self by default" do
      Timeout.new(5) |> Timeout.send_after(:msg)
      assert_receive :msg, 10
    end

    test "sends a message to another process" do
      pid = spawn fn -> assert_receive :msg, 10 end
      Timeout.new(5) |> Timeout.send_after(pid, :msg)
    end

    test "sends a message using the current static timeout" do
      timeout = Timeout.new(5)
      assert {_, 5} = Timeout.send_after(timeout, :msg)
      assert_receive :msg, 10
    end

    test "sends the next timeout when :backoff is configured" do
      timeout = Timeout.new(20, backoff: 1.25) |> Timeout.next()
      assert {%{timeout: 25}, 25} = Timeout.send_after(timeout, :msg)
      assert_receive :msg, 30
    end

    test "sends the next timeout when :random is configured" do
      timeout = Timeout.new(100, random: 0.1)
      assert {_, delay} = Timeout.send_after(timeout, :msg)
      assert delay in 91..110
      assert_receive :msg, delay + 5
    end
  end

  describe ".send_after!/3" do
    test "sends the message and returns the Timeout" do
      timeout = Timeout.new(5)
      assert %Timeout{} = Timeout.send_after!(timeout, :msg)
      assert_receive :msg, 10
    end
  end

  describe ".cancel_timer/1" do
    test "cancels the stored timer" do
      timeout = Timeout.new(10) |> Timeout.send_after!(:msg)
      assert {%{timer: nil}, result} = Timeout.cancel_timer(timeout)
      assert result <= 10
      refute_receive :msg, 10
    end

    test "returns a false result when there is no timer" do
      timeout = Timeout.new(10)
      assert {^timeout, false} = Timeout.cancel_timer(timeout)
    end
  end

  describe ".cancel_timer!/1" do
    test "cancels the timer and returns the Timeout" do
      timeout = Timeout.new(10) |> Timeout.send_after!(:msg)
      assert %{timer: nil} = Timeout.cancel_timer!(timeout)
      refute_receive :msg, 10
    end
  end
end
