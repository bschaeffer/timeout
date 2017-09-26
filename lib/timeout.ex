defmodule Timeout do
  @moduledoc """
  An module for manipulating configurable timeouts.

  Comes with the following features.

  * Randomizing within +/- of a given percent range
  * Backoffs with an optional maximum.
  * Timer management using the above configuration.

  ### Backoff

  Backoffs can be configured using the `:backoff` and `:backoff_max` options
  when creating a timeout with `new/1`. Each call to `next/1` will increment the
  timeout by the given backoff and store that new value as the current timeout.

  This comes in handy when you might want to backoff a reconnect attempt or a
  polling process during times of low activity.

      t = Timeout.new(100, backoff: 1.25)
      Timeout.current(t) # => 100
      t = Timeout.next(t)
      Timeout.current(t) # => 100
      t = Timeout.next(t)
      Timeout.current(t) # => 125
      t = Timeout.next(t)
      Timeout.current(t) # => 156

  *Note* how the first call to next returns the initial value. If we incremented
  it on the first call, the initial value would never be used.

  ### Randomizing

  This module is capabable of randomizing within `+/-` of a given percent range.
  This feature can be especially useful if you want to avoid something like the
  [Thundering Heard Problem][thp] when multiple processes might be sending
  requests to a remote service. For example:

      t = Timeout.new(100, random: 0.10)
      Timeout.current(t) # => 95
      Timeout.current(t) # => 107
      Timeout.current(t) # => 108
      Timeout.current(t) # => 99
      Timeout.current(t) # => 100

  This works in combination with the `backoff` configuration as well:

      t = Timeout.new(100, backoff: 1.25, random: 0.10)
      t = Timeout.next(t)
      Timeout.current(t) # => Within +/- 10% of 100
      t = Timeout.next(t)
      Timeout.current(t) # => Within +/- 10% of 125
      t = Timeout.next(t)
      Timeout.current(t) # => Within +/- 10% of 156

  ### Timers

  The main reason for writing this library was to be able to configure a timeout
  once, then be able to schedulle server messages without having to keep track
  of the timeout values being used.

  After configuring your timeout using the options above, you can start
  scheduling messages using the following workflow:

      t = Timeout.new(100, backoff: 1.25, backoff_max: 1_250, random: 0.10)
      {t, delay} = Timeout.send_after(t, self(), :message)
      IO.puts("Message delayed for: \#{delay}")
      receive do
        :message -> IO.puts("Received message!")
      end

  The timer API methods include:

  * `send_after/3`: Sends the message, returns `{timeout, delay}`.
  * `send_after!/3`: Same as above, but just returns the timeout.
  * `cancel_timer/1`: Cancels the stored timer, returns `{timeout, result}`.
  * `cancel_timer!/1`: Same as above, but just returns the timeout.

  [thp]: https://en.wikipedia.org/wiki/Thundering_herd_problem
  """
  @type timeout_value :: pos_integer

  @typedoc "Represents timeout growth factor. Should be `> 1`."
  @type backoff :: pos_integer | float | nil

  @typedoc "Represents the max growth of a timeout using backoff."
  @type backoff_max:: pos_integer | nil

  @typedoc "Represents a % range when randomizing. Should be `0 < x < 1`."
  @type random :: float | nil

  @type options :: [backoff: backoff, backoff_max: backoff_max, random: random]


  @type t :: %__MODULE__{
    base: timeout_value,
    timeout: timeout_value,
    backoff: backoff,
    backoff_round: non_neg_integer,
    backoff_max: backoff_max,
    random: {float, float} | nil,
    timer: reference | nil
  }

  defstruct ~w(base timeout backoff backoff_round backoff_max random timer)a

  @doc """
  Builds a `Timeout` struct.

  Accepts an integer timeout value and the following optional configuration:

  * `:backoff` - A backoff growth factor for growing a timeout period over time.
  * `:backoff_max` - Given `:backoff`, will never grow past max.
  * `:random` - A float indicating the `%` timeout values will be randomized
    within. Expects `0 < :random < 1` or raises an `ArgumentError`. For example,
    use `0.10` to randomize within +/- 10% of the desired timeout.

  For more information, see `Timeout`.
  """
  @spec new(timeout_value, options) :: t
  def new(timeout, opts \\ []) when is_integer(timeout) do
    %__MODULE__{
      base: timeout,
      timeout: timeout,
      backoff: Keyword.get(opts, :backoff),
      backoff_round: 0,
      backoff_max: Keyword.get(opts, :backoff_max),
      random: opts |> Keyword.get(:random) |> parse_random_max_min()
    }
  end

  @doc """
  Resets the current timeout.
  """
  @spec reset(t) :: t
  def reset(t = %__MODULE__{base: base}) do
    %{t | backoff_round: 0, timeout: base}
  end

  @doc """
  Increments the current timeout based on the `backoff` configuration.

  If there is no `backoff` configured, this function simply returns the timeout
  as is. If `backoff_max` is configured, the timeout will never be incremented
  above that value.

  **Note:** The first call to `next/1` will always return the initial timeout
  first.
  """
  @spec next(t) :: t
  def next(t = %__MODULE__{backoff: nil}), do: t
  def next(t = %__MODULE__{base: base, timeout: nil}), do: %{t | timeout: base}
  def next(t = %__MODULE__{timeout: c, backoff_max: c}), do: t
  def next(t = %__MODULE__{base: c, backoff: b, backoff_round: r, backoff_max: m}) do
    timeout = round(c * :math.pow(b, r))
    %{t | backoff_round: r + 1, timeout: (m && (timeout > m and m)) || timeout}
  end

  @doc """
  Returns the timeout value represented by the current state.

      iex> Timeout.new(100) |> Timeout.current()
      100

  If `backoff` was configured, returns the current timeout with backoff applied:

      iex> t = Timeout.new(100, backoff: 1.25) |> Timeout.next() |> Timeout.next()
      ...> Timeout.current(t)
      125

  If `random` was configured, the current timeout out is randomized within the
  configured range:

      iex> t = Timeout.new(100, random: 0.10)
      ...> if Timeout.current(t) in 91..110, do: true, else: false
      true
  """
  @spec current(t) :: timeout_value
  def current(%__MODULE__{base: base, timeout: nil, random: random}),
    do: calc_current(base, random)
  def current(%__MODULE__{timeout: timeout, random: random}),
    do: calc_current(timeout, random)

  @doc """
  Sends a process a message with `Process.send_after/3` using the given timeout,
  the stores the resulting timer on the struct.

  Sends the message to `self()` if pid is omitted, otherwise sends to the given
  `pid`.

  Always calls `next/1` first on the given timer, then uses the return value of
  `current/1` to delay the message.

  This function is a convienence wrapper around the following workflow:

      t = Timeout.new(100, backoff: 1.25) |> Timeout.next()
      timer = Process.send_after(self(), :message, Timeout.current(t))
      t = %{t | timer: timer}

  Returns `{%Timeout{}, delay}` where delay is the message schedule delay.
  """
  @spec send_after(t, pid, term) ::{t, pos_integer}
  def send_after(t = %__MODULE__{}, pid \\ self(), message) do
    t = next(t)
    delay = current(t)
    {%{t | timer: Process.send_after(pid, message, delay)}, delay}
  end

  @doc """
  Calls `send_after/3`, but returns only the timeout struct.
  """
  @spec send_after!(t, pid, term) :: t
  def send_after!(t = %__MODULE__{}, pid \\ self(), message) do
    with {timeout, _delay} <- send_after(t, pid, message), do: timeout
  end

  @doc """
  Cancels the stored timer.

  Returns `{%Timeout{}, result}` where result is the value returned by calling
  `Process.cancel_timer/1` on the stored timer reference.
  """
  @spec cancel_timer(t) :: {t, non_neg_integer | false | :ok}
  def cancel_timer(t = %__MODULE__{timer: nil}), do: {t, false}
  def cancel_timer(t = %__MODULE__{timer: timer}) when is_reference(timer) do
    {%{t | timer: nil}, Process.cancel_timer(timer)}
  end

  @doc """
  Calls `cancel_timer/1` but returns only the timeout struct.

  Returns `{%Timeout{}, result}` where result is the value returned by calling
  `Process.cancel_timer/1` on the stored timer reference.
  """
  @spec cancel_timer!(t) :: t
  def cancel_timer!(t = %__MODULE__{}) do
    with {timeout, _result} <- cancel_timer(t), do: timeout
  end

  defp calc_current(timeout, nil), do: timeout
  defp calc_current(timeout, {rmax, rmin}) do
    max = round(timeout * rmax)
    min = round(timeout * rmin)
    min + do_rand(max - min)
  end

  defp parse_random_max_min(nil), do: nil
  defp parse_random_max_min(range) when is_float(range) and range > 0 and range < 1 do
    {1.0 + range, 1.0 - range}
  end
  defp parse_random_max_min(range) do
    raise ArgumentError, "Invalid option for :random. Expected 0 < float < 1, got: #{range}"
  end

  defp do_rand(0), do: 0
  defp do_rand(n), do: :rand.uniform(n)
end
