defmodule Ecto.Adapters.Neo4j.Schema do
  @moduledoc """
  Helps to describe graph schema.

  -> Adds `:uuid` as default primary key

  -> Provides 2 helpers to manage relationship:
    - outgoing_relationship
    - incoming relationship
  """
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Adapters.Neo4j.Schema
      @primary_key {:uuid, Ecto.UUID, []}
    end
  end

  @doc """
  Decribe a outgoing relationship for current `Ecto.Schema` to given `Ecto.Schema`

  IMPORTANT:
  - association name has to be formated as : *[relationship_name]*_*[child_schema_name]*
  - an `incoming_relationship` with the exact same name has to be added in the child schema.

  ## Example

      # Describes a relationship: (User)-[:WROTE]->(Post)
      schema "User" do
        outgoing_relationship :wrote_post, EctoNeo4j.Integration.Post
      end

  # Options
    `:unique`: set to `true`, the association will be a `has_one`.
    Set to `false`, association will be `has_many`. [Default: false]
  """
  defmacro outgoing_relationship(name, queryable, opts \\ []) do
    quote do
      opts = unquote(opts)

      if Keyword.get(opts, :unique, false) do
        has_one unquote(name), unquote(queryable),
          foreign_key: unquote(name) |> build_foreign_key(),
          on_replace: :delete
      else
        has_many unquote(name), unquote(queryable),
          foreign_key: unquote(name) |> build_foreign_key(),
          on_replace: :delete
      end
    end
  end

  @doc """
  Decribe a incoming relationship for current `Ecto.Schema` to given `Ecto.Schema`

  IMPORTANT:
  - association name has to be formated as : *[relationship_name]*_*[child_schema_name]*
  - an `outgoing_relationship` with the exact same name has to be added in the parent schema.

  ## Example

      # Describes a relationship: (User)-[:WROTE]->(Post)
      schema "Post" do
        incoming_relationship :wrote_post, EctoNeo4j.Integration.User
      end

  # Options
    `:unique`: set to `true`, the association will be a `has_one`.
    Set to `false`, association will be `has_many`. [Default: false]
  """
  defmacro incoming_relationship(name, queryable, _opts \\ []) do
    quote do
      foreign_key =
        unquote(name)
        |> Atom.to_string()
        |> Kernel.<>("_uuid")
        |> String.to_atom()

      belongs_to unquote(name), unquote(queryable),
        foreign_key: foreign_key,
        type: Ecto.UUID,
        references: :uuid,
        on_replace: :delete
    end
  end

  @spec build_foreign_key(atom()) :: atom()
  def build_foreign_key(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_uuid")
    |> String.to_atom()
  end
end
