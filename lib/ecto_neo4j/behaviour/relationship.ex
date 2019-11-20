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
    Enum.map(module.__schema__(:associations), &manage_assoc(data, &1))
    result
  end

  def process_relationships(result) do
    result
  end

  @spec manage_assoc(map(), map()) :: :ok | {:error, any()}
  defp manage_assoc(data, assoc) do
    Enum.each(Map.get(data, assoc), fn data_assoc ->
      {cql, params} =
        data_assoc
        |> extract_relationship(format_node(data), format_node(data_assoc))
        |> EctoNeo4j.Cql.Relationship.create()

      Ecto.Adapters.Neo4j.query(cql, params)
    end)
  end

  @spec extract_relationship(map(), Node.t(), Node.t()) :: Relationship.t()
  defp extract_relationship(data, start_node, end_node) do
    Enum.filter(Map.from_struct(data), fn {k, _v} ->
      case Atom.to_string(k) do
        "rel" <> _rel_type -> true
        _ -> false
      end
    end)
    |> List.first()
    |> format_relationship(start_node, end_node)
  end

  @spec format_relationship({atom(), map()}, Node.t(), Node.t()) :: Relationship.t()
  defp format_relationship({rel_type_atom, properties}, start_node, end_node) do
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

  @spec format_node(map()) :: Node.t()
  defp format_node(%{__struct__: module} = data) do
    %Node{
      labels: [module.__schema__(:source)],
      id: Map.get(data, :id) || Map.get(data, :uuid),
      properties: Map.drop(data, [:id, :uuid])
    }
  end
end
