defmodule EctoNeo4j.MixProject do
  use Mix.Project

  def project do
    [
      name: "EctoNeo4j",
      app: :ecto_neo4j,
      version: "0.5.2",
      elixir: "~> 1.8",
      package: package(),
      description: "Ecto adapter for Neo4j graph database",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      source_url: "https://github.com/dominique-vassard/ecto_neo4j",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package() do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["Dominique VASSARD"],
      links: %{"Github" => "https://github.com/dominique-vassard/ecto_neo4j"}
    }
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.2"},
      {:ecto_sql, "~> 3.2"},
      {:bolt_sips, "~> 2.0"},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false}
    ]
  end
end
