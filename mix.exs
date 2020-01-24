defmodule EctoNeo4j.MixProject do
  use Mix.Project

  def project do
    [
      name: "EctoNeo4j",
      app: :ecto_neo4j,
      version: "0.6.3",
      elixir: "~> 1.8",
      package: package(),
      description: "Ecto adapter for Neo4j graph database",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
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
      assets: "assets",
      main: "readme",
      extras: extras(),
      groups_for_extras: groups_for_extras()
    ]
  end

  defp extras do
    [
      "README.md",
      "guide/up_and_running.md",
      "guide/schema.md",
      "guide/inserting.md",
      "guide/querying.md",
      "guide/updating_and_deleting.md"
    ]
  end

  defp groups_for_extras do
    [
      Guide: ~r/guide\/[^\/]+\.md/
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.2"},
      {:ecto_sql, "~> 3.2"},
      {:bolt_sips, "~> 2.0"},
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [docs: ["docs", &copy_images/1]]
  end

  defp copy_images(_) do
    File.cp_r("assets", "doc/assets", fn source, destination ->
      IO.gets("Overwriting #{destination} by #{source}. Type y to confirm. ") == "y\n"
    end)

    File.cp_r("doc", "docs", fn _source, _destination ->
      true
    end)
  end
end
