defmodule Ecto.Adapters.Neo4j.Behaviour.Relationship do
  @moduledoc """
  Manage relationship operation
  """
  # alias Bolt.Sips.Types.{Node, Relationship}
  alias Ecto.Adapters.Neo4j.Query
  alias Ecto.Adapters.Neo4j.Condition

  @doc """
  Create the necessary relationship for the given schema data.
  Retrieve all the associations and translate them into relationships.
  """
  @spec process_relationships({:ok, Ecto.Schema.t()}) :: Ecto.Schema.t()
  def process_relationships({:ok, %{__struct__: _module} = data} = result) do
    do_process_relationships(data)

    result
  end

  def process_relationships(result) do
    result
  end

  defp do_process_relationships(%Ecto.Association.NotLoaded{}) do
    :ok
  end

  defp do_process_relationships(%{__struct__: module} = data) do
    Enum.each(module.__schema__(:associations), fn assoc ->
      if Kernel.match?(%Ecto.Association.Has{}, module.__schema__(:association, assoc)) do
        manage_assoc(data, assoc, Map.get(data, assoc))
        do_process_relationships(Map.get(data, assoc))
      end
    end)
  end

  defp do_process_relationships(data) when is_list(data) do
    Enum.each(data, fn d ->
      do_process_relationships(d)
    end)
  end

  defp do_process_relationships(nil) do
    :ok
  end

  defp manage_assoc(_data, _assoc, %Ecto.Association.NotLoaded{}) do
    :ok
  end

  defp manage_assoc(data, assoc, data_assoc) when is_list(data_assoc) do
    Enum.each(data_assoc, &do_manage_assoc(data, assoc, &1))
  end

  defp manage_assoc(data, assoc, data_assoc) do
    manage_assoc(data, assoc, [data_assoc])
  end

  defp do_manage_assoc(data, assoc, data_assoc) do
    start_node = node_info(data)
    end_node = node_info(data_assoc)

    rel_type =
      assoc
      |> Atom.to_string()
      |> String.replace("_" <> String.downcase(end_node.label), "")
      |> String.upcase()

    match = [
      start_node.expr,
      end_node.expr
    ]

    relationship = %Query.RelationshipExpr{
      start: Map.put(start_node.expr, :labels, nil),
      end: Map.put(end_node.expr, :labels, nil),
      type: rel_type,
      variable: "rel"
    }

    %{sets: sets, params: params} =
      Map.fetch!(data_assoc, String.to_atom("rel_" <> String.downcase(rel_type)))
      |> Enum.reduce(%{sets: [], params: %{}}, fn {prop_name, value}, data ->
        set = %Query.SetExpr{
          field: %Query.FieldExpr{
            variable: relationship.variable,
            name: prop_name
          },
          value: Atom.to_string(prop_name)
        }

        params = Map.put(%{}, prop_name, value)

        %{data | sets: data.sets ++ [set], params: Map.merge(data.params, params)}
      end)

    wheres =
      (build_where(start_node) ++ build_where(end_node))
      |> Enum.reduce(%{condition: nil, params: %{}}, fn where, acc ->
        %{
          acc
          | condition: Condition.join_conditions(acc.condition, where.condition, :and),
            params: Map.merge(acc.params, where.params)
        }
      end)

    params = Map.merge(params, wheres.params)

    merge = %Query.MergeExpr{
      expr: relationship,
      on_create: sets
    }

    {cql, params} =
      Query.new(:merge)
      |> Query.match(match)
      |> Query.merge(merge)
      |> Query.where(wheres.condition)
      |> Query.params(params)
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)
  end

  defp node_info(%{__struct__: module} = data) do
    label = module.__schema__(:source)

    %{
      data: data,
      label: label,
      expr: %Query.NodeExpr{
        labels: [label],
        variable: String.downcase(label)
      },
      primary_keys: module.__schema__(:primary_key)
    }
  end

  defp build_where(node_data) do
    Enum.map(node_data.primary_keys, fn pk ->
      field_var = node_data.expr.variable <> Atom.to_string(pk)

      condition = %Condition{
        source: node_data.expr.variable,
        field: pk,
        operator: :==,
        value: field_var
      }

      %{
        condition: condition,
        params: Map.put(%{}, String.to_atom(field_var), Map.fetch!(node_data.data, pk))
      }
    end)
  end
end
