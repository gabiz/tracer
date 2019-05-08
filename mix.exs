defmodule Tracer.Mixfile do
  use Mix.Project

  @version File.read!("VERSION.md") |> String.trim

  def project do
    [app: :tracer,
     version: @version,
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     deps: deps(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: ["coveralls": :test, "coveralls.detail":
              :test, "coveralls.post": :test, "coveralls.html": :test],
     docs: [extras: ["README.md"]]]
  end

  def application do
    [mod: {Tracer.App, []},
     extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.7", only: :test},
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Elixir Tracing Framework.
    """
  end

  defp package do
    [files: ~w(lib test scripts mix.exs README.md LICENSE.md VERSION.md),
     maintainers: ["Gabi Zuniga"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/gabiz/tracer"}]
  end

end
