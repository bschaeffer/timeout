# Timeout

A configurable struct for managing timeouts. Features include:

* Static timeouts.
* Backoffs with optional max.
* Randomizing within a given range.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `timeout` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:timeout, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/timeout](https://hexdocs.pm/timeout).
