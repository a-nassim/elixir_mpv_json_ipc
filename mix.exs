defmodule MpvJsonIpc.MixProject do
  use Mix.Project

  def project do
    [
      app: :mpv_json_ipc,
      version: "0.1.2",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: [
        extras: ["README.md"] ++ Path.wildcard("pages/*.md"),
        main: "readme",
        source_url: "https://github.com/a-nassim/elixir_mpv_json_ipc"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MpvJsonIpc.Application, []},
      env: [timeout: :timer.seconds(30)]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false},
      {:jason, "~> 1.4"}
    ]
  end

  defp description() do
    "Elixir API to MPV using JSON IPC."
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/a-nassim/elixir_mpv_json_ipc"}
    ]
  end
end
