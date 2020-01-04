defmodule Ecto.Adapters.Neo4j.Schema do
  require Ecto.Schema

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
