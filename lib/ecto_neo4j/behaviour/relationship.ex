defmodule EctoNeo4j.Behaviour.Relationship do
  @moduledoc """
  Manage relationship operation
  """
  alias Bolt.Sips.Types.{Node, Relationship}

  @doc """
  Create the necessary relationship for the given schema data.
  Retrieve al the associations and translate them into relationships.
  """
  @spec process_relationships({:ok, Ecto.Schema.t()}) :: Ecto.Schema.t()
  def process_relationships({:ok, %{__struct__: module} = data} = result) do
    Enum.map(module.__schema__(:associations), fn assoc ->
      manage_assoc(data, Map.get(data, assoc))
    end)

    result
  end

  def process_relationships(result) do
    result
  end

  @spec manage_assoc(map(), Ecto.Association.NotLoaded.t() | map()) :: :ok | {:error, any()}
  defp manage_assoc(_, %Ecto.Association.NotLoaded{}) do
    :ok
  end

  defp manage_assoc(data, data_assoc) do
    Enum.each(data_assoc, fn data_assoc ->
      data_assoc
      |> extract_relationships()
      |> Enum.map(fn relationship ->
        insert_relationship(relationship, format_node(data), format_node(data_assoc))
      end)
    end)
  end

  @spec insert_relationship(Relationship.t(), Node.t(), Node.t()) ::
          {:ok, Bolt.Sips.Response.t()} | {:error, any()}
  defp insert_relationship(relationship, start_node, end_node) do
    {cql, params} =
      relationship
      |> format_relationship(start_node, end_node)
      |> EctoNeo4j.Cql.Relationship.create()

    Ecto.Adapters.Neo4j.query(cql, params)
  end

  # Extract valid realtionship from data
  # A relationship with `nil` as properties is not valid
  @spec extract_relationships(map()) :: [Relationship.t()]
  defp extract_relationships(data) do
    Enum.filter(Map.from_struct(data), fn
      {k, v} when not is_nil(v) ->
        case Atom.to_string(k) do
          "rel" <> _rel_type -> true
          _ -> false
        end

      _ ->
        false
    end)
  end

  @spec format_relationship({atom(), map()}, Node.t(), Node.t()) :: Relationship.t()
  defp format_relationship({rel_type_atom, properties}, start_node, end_node)
       when is_map(properties) do
    rel_type =
      rel_type_atom
      |> Atom.to_string()
      |> String.replace_prefix("rel_", "")
      |> String.upcase()

    %Relationship{
      type: rel_type,
      properties: properties,
      start: start_node,
      end: end_node
    }
  end

  defp format_relationship({_, nil}, _, _) do
    nil
  end

  @spec format_node(map()) :: Node.t()
  defp format_node(%{__struct__: module} = data) do
    %Node{
      labels: [module.__schema__(:source)],
      id: Map.get(data, :id) || Map.get(data, :uuid),
      properties: Map.drop(data, [:id, :uuid])
    }
  end
end
