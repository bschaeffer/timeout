defmodule Timeout do
  @moduledoc """
  Module for dealing with configurable timeouts.
  """
  @type timeout_value :: non_neg_integer | nil
  @type backoff :: number | nil
  @type backoff_max:: non_neg_integer | nil
  @type random :: float | nil
  @type options :: [backoff: backoff, backoff_max: backoff_max, random: random]

  @type t :: %__MODULE__{
    base: timeout_value,
    timeout: timeout_value,
    backoff: backoff,
    backoff_max: backoff_max,
    random: {float, float} | nil,
    timer: reference | nil
  }

  defstruct [:base, :timeout, :backoff, :backoff_max, :random, :timer]

  @spec new(timeout_value, options) :: t
  def new(timeout, opts \\ []) when is_integer(timeout) do
    %__MODULE__{
      base: timeout,
      timeout: timeout,
      backoff: Keyword.get(opts, :backoff),
      backoff_max: Keyword.get(opts, :backoff_max),
      random: opts |> Keyword.get(:random) |> parse_random_max_min()
    }
  end

  @doc """
  Resets the current timeout to the base value.

      iex> t = Timeout.new(100, backoff: 1.25) |> Timeout.next()
      %Timeout{base: 100, timeout: 125, backoff: 1.25, backoff_max: nil, random: nil}
      ...> Timeout.reset(t)
      %Timeout{base: 100, timeout: 100, backoff: 1.25, backoff_max: nil, random: nil}
  """
  @spec reset(t) :: t
  def reset(t = %__MODULE__{base: base}), do: %{t | timeout: base}

  @doc """
  Returns the next timeout in the series.

  When there is no `backoff` parameter, always returns the base timeout:

      iex> Timeout.new(100) |> Timeout.next()
      %Timeout{base: 100, timeout: 100, backoff: nil, backoff_max: nil, random: nil}

  When there is a configured `backoff`, returns the next timeout based on the
  growth factor:

      iex> t = Timeout.new(100, backoff: 1.25) |> Timeout.next()
      %Timeout{base: 100, timeout: 125, backoff: 1.25, backoff_max: nil, random: nil}
      ...> Timeout.next(t)
      %Timeout{base: 100, timeout: 156, backoff: 1.25, backoff_max: nil, random: nil}

  When there is a configured `backoff_max`, and we're over that max.

      iex> t = Timeout.new(100, backoff: 1.25, backoff_max: 150)
      ...> t = Timeout.next(t)
      %Timeout{base: 100, timeout: 125, backoff: 1.25, backoff_max: 150, random: nil}
      ...> t = Timeout.next(t)
      %Timeout{base: 100, timeout: 150, backoff: 1.25, backoff_max: 150, random: nil}
      ...>Timeout.next(t)
      %Timeout{base: 100, timeout: 150, backoff: 1.25, backoff_max: 150, random: nil}
  """
  @spec next(t) :: t
  def next(t = %__MODULE__{backoff: nil}), do: t
  def next(t = %__MODULE__{timeout: timeout, backoff: backoff, backoff_max: nil}) do
    %{t | timeout: round(timeout * backoff)}
  end
  def next(t = %__MODULE__{timeout: timeout, backoff: backoff, backoff_max: max}) do
    next_timeout = round(timeout * backoff)
    %{t | timeout: (next_timeout > max and max) || next_timeout}
  end

  @doc """
  Returns the actual timeout value.

      iex> t = Timeout.new(100, backoff: 1.25) |> Timeout.next()
      ...> Timeout.current(t)
      125

  If `random` was configured, the current timeout out is randomized between the
  given range:

      iex> t = Timeout.new(100, random: 0.10)
      ...> timeout = Timeout.current(t)
      ...> if timeout in 90..110, do: true, else: false
      true
  """
  @spec current(t) :: timeout_value
  def current(%__MODULE__{timeout: timeout, random: nil}), do: timeout
  def current(%__MODULE__{timeout: timeout, random: {rmax, rmin}}) do
    min = round(timeout * rmin) + 1 # + 1 so we never get 0.
    max = round(timeout * rmax)
    min + :rand.uniform(max - min)
  end


  @doc """
  Delegates to `Process.send_after/3` using the timeout returned by `current/1`
  and stores the resulting timer on the struct.

      iex> Timeout.new(100) |> Timeout.send_after(self(), :yolo)
      ...> receive do
      ...>   :yolo -> :received
      ...> after
      ...>   110 -> :not_received
      ...> end
      :received
  """
  @spec send_after(t, pid, term) :: t
  def send_after(t = %__MODULE__{}, pid, msg) when is_pid(pid) do
    if is_reference(t.timer), do: Process.cancel_timer(t.timer)
    %{t | timer: Process.send_after(pid, msg, current(t))}
  end

  @doc """
  Calls `next/1` then delegates `send_after/3`.

      iex> t = Timeout.new(100, backoff: 2)
      ...> Timeout.send_after_next(t, self(), :yolo)
      ...> receive do
      ...>   :yolo -> :received
      ...> after
      ...>   210 -> :not_received
      ...> end
      :received
  """
  @spec send_after_next(t, pid, term) :: t
  def send_after_next(timeout = %__MODULE__{}, pid, msg) when is_pid(pid) do
    timeout |> next() |> send_after(pid, msg)
  end

  @doc """
  Cancels the current timer stored on the struct via `Process.cancel_timer/1`.

  Return the result of the cancel call and the new timeout struct as a 2-element
  tuple:

  When there is no timer:

      iex> t = Timeout.new(100)
      ...> {false, t} = Timeout.cancel_timer(t)
      ...> t.timer
      nil

  When there is a timer:

      iex> t = Timeout.new(1000) |> Timeout.send_after(self(), :yolo)
      ...> {_time_remaining, t} = Timeout.cancel_timer(t)
      ...> t.timer
      nil
  """
  @spec cancel_timer(t) :: {false | non_neg_integer, t}
  def cancel_timer(t = %__MODULE__{timer: nil}), do: {false, t}
  def cancel_timer(t = %__MODULE__{timer: timer}) when is_reference(timer) do
    {Process.cancel_timer(timer), %{t | timer: nil}}
  end

  defp parse_random_max_min(nil), do: nil
  defp parse_random_max_min(range) when is_float(range) and range > 0 and range < 1 do
    {1.0 + range, 1.0 - range}
  end
  defp parse_random_max_min(range) do
    raise ArgumentError, "Invalid option for :random. Expected 0 < float < 1, got: #{range}"
  end
end
