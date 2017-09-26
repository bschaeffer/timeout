defmodule Timeout.Mixfile do
  use Mix.Project

  @version "0.3.0"
  @description "A module for working with configurable timeouts."
  @repo_url "https://github.com/bschaeffer/timeout"

  def project do
    [
      app: :timeout,
      version: @version,
      elixir: "~> 1.4",
      start_permanent: Mix.env == :prod,
      deps: deps(),

      # Hex
      description: @description,
      package: package(),

      # ExDoc
      name: "Timeout",
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        source_url: @repo_url,
        extras: ["README.md"]
      ]
    ]
  end

  def package do
    [
      maintainers: ["Braden Schaeffer"],
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.15", only: :dev}
    ]
  end
end
