# Timeout

[![CircleCI](https://circleci.com/gh/bschaeffer/timeout.svg?style=svg)](https://circleci.com/gh/bschaeffer/timeout)
[![hex.pm](https://img.shields.io/hexpm/v/timeout.svg "Hex version")](https://hex.pm/packages/timeout)


`Timeout` is an api for managing and manipulating configurable timeouts. It was
mainly built as a library to configure a timeout once, then start scheduling
messages based on the configuration. It's features include:

* API for retrieving and iterating timeouts.
* Timeout backoff with optional max.
* Randomizing within a given percent of a desired range.
* Timer management utilizing the above configuration.

Read the docs at https://hexdocs.pm/timeout.

## Example Usage

A simple example using a `GenServer` process polling a remote service for work:

```elixir
defmodule MyPoller do
  use GenServer
  require Logger

  def start_link(backend) do
    GenServer.start_link(__MODULE__, [backend])
  end

  def init(backend) do
    timeout =
      Timeout.new(50, backoff: 1.25, backoff_max: 1_250, random: 0.1)
      |> Timeout.send_after(self(), :poll)

    {:ok, %{backend, timeout}}
  end

  def handle_info(:poll, {backend, timeout}) do
    case backend.poll() do
      {:ok, job} ->
        # Process job. Reset timeout to poll at the initial interval.
        timeout = Timeout.reset() |> Timeout.send_after!(:poll)
        {:noreply, {backend, timeout}}
      :empty ->
        # No work to do. Send after automatically increases the backoff
        {timeout, delay} = timeout |> Timeout.send_after(:poll)
        Logger.debug("No work. Retrying in #{delay}ms")
        {:noreply, {backend, timeout}}
    end
  end

  def handle_info({:new_job, job}, {backend, timeout}) do
    Timeout.cancel_timer!(timeout)
    # Process job
    timeout = timeout |> Timeout.reset() |> Timeout.send_after!(:poll)
    {:noreply, {backend, timeout}}
  end
end
```

See the docs for more information: https://hexdocs.pm/timeout.

## Installation

Add `timeout` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:timeout, "~> 0.2.0"}
  ]
end
```

[thp]: https://en.wikipedia.org/wiki/Thundering_herd_problem
