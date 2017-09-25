defmodule Timeout.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :timeout,
      version: @version,
      elixir: "~> 1.4",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    []
  end
end
