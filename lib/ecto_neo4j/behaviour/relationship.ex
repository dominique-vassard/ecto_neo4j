defmodule Ecto.Adapters.Neo4j.Behaviour.Relationship do
  @moduledoc """
  Manage relationship operation
  """
  alias Ecto.Adapters.Neo4j.Query
  alias Ecto.Adapters.Neo4j.Condition

  @doc """
  Create the necessary relationships for the given schema data.
  Extract data from the `has_many` and `has_one` associations and convert them into relationships.

  Note that only 1-depth assocations are treated.
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
      |> Query.merge([merge])
      |> Query.where(wheres.condition)
      |> Query.params(params)
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)
  end

  # TODO: On creation, set relationship data...
  def update(:update, node1_data, node2_data, rel_name) do
    {relationship_data, %{where: where, params: params}} =
      build_relationship_and_clauses(node1_data, node2_data, rel_name)

    relationship =
      relationship_data
      |> Map.put(:start, Map.drop(relationship_data.start, [:labels]))
      |> Map.put(:end, Map.drop(relationship_data.end, [:labels]))

    {cql, params} =
      Query.new(:create)
      |> Query.match([
        relationship_data.start,
        relationship_data.end
      ])
      |> Query.merge([
        %Query.MergeExpr{
          expr: relationship
        }
      ])
      |> Query.where(where)
      |> Query.params(params)
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)

    add_fk_data(node1_data, node2_data, rel_name)
    # node2_data
  end

  def update(:replace, node1_data, node2_data, rel_name) do
    {relationship, %{where: where, params: params}} =
      build_relationship_and_clauses(node1_data, node2_data, rel_name)

    {cql, params} =
      Query.new(:delete)
      |> Query.match([relationship])
      |> Query.delete([relationship])
      |> Query.where(where)
      |> Query.params(params)
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)
    nil
  end

  def update_data(node_schema, rel_field, changes, data) do
    "rel_" <> rel_type = Atom.to_string(rel_field)

    mod =
      Module.split(node_schema)
      |> List.last()
      |> String.downcase()

    assoc = String.to_atom(rel_type <> "_" <> mod)

    case node_schema.__schema__(:association, assoc) do
      %Ecto.Association.BelongsTo{queryable: queryable} ->
        {relationship, %{where: where, params: params}} =
          build_relationship_and_clauses(data, queryable, assoc)

        %{sets: sets, params: set_params} =
          Enum.reduce(changes, %{sets: [], params: %{}}, fn {field, value}, sets_data ->
            bound_name = relationship.variable <> "_" <> Atom.to_string(field)

            set = %Query.SetExpr{
              field: %Query.FieldExpr{
                variable: relationship.variable,
                name: field
              },
              value: bound_name
            }

            %{
              sets_data
              | sets: sets_data.sets ++ [set],
                params: Map.put(sets_data.params, String.to_atom(bound_name), value)
            }
          end)

        {cql, params} =
          Query.new(:update)
          |> Query.match([relationship])
          |> Query.where(where)
          |> Query.set(sets)
          |> Query.params(Map.merge(params, set_params))
          |> Query.to_string()

        Ecto.Adapters.Neo4j.query!(cql, params)

      %{__struct__: st} ->
        raise "#{inspect(st)} is not supported"
    end
  end

  def build_relationship_and_clauses(node1_data, node2_data, rel_name) do
    n1_data = node_info(node1_data)
    n2_data = node_info(node2_data)

    %{__struct__: node1_schema} = node1_data

    {start_node, end_node, queryable} =
      case node1_schema.__schema__(:association, rel_name) do
        %Ecto.Association.BelongsTo{queryable: queryable} ->
          {n2_data.expr, n1_data.expr, queryable}

        %{queryable: queryable} ->
          {n1_data.expr, n2_data.expr, queryable}
      end

    rel_type = extract_relationship_type(rel_name, queryable, node1_schema)

    relationship = %Query.RelationshipExpr{
      start: start_node,
      end: end_node,
      type: rel_type,
      variable: "rel"
    }

    wheres =
      (build_where(n1_data) ++ build_where(n2_data))
      |> Enum.reduce(%{where: nil, params: %{}}, fn where, acc ->
        %{
          acc
          | where: Condition.join_conditions(acc.where, where.condition, :and),
            params: Map.merge(acc.params, where.params)
        }
      end)

    {relationship, wheres}
  end

  defp extract_relationship_type(rel_name, queryable, node_schema) do
    rel_type =
      String.replace(
        Atom.to_string(rel_name),
        "_" <> String.downcase(queryable.__schema__(:source)),
        ""
      )

    if rel_type == Atom.to_string(rel_name) do
      String.replace(
        Atom.to_string(rel_name),
        "_" <> String.downcase(node_schema.__schema__(:source)),
        ""
      )
    else
      rel_type
    end
    |> String.upcase()
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

  defp node_info(schema) when is_atom(schema) do
    label = schema.__schema__(:source)

    %{
      data: nil,
      label: label,
      expr: %Query.NodeExpr{
        labels: [label],
        variable: String.downcase(label)
      },
      primary_keys: []
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

  defp add_fk_data(parent, child, field) do
    %{__struct__: child_schema} = child

    Enum.reduce(child_schema.__schema__(:associations), nil, fn assoc, result ->
      case child_schema.__schema__(:association, assoc) do
        %Ecto.Association.BelongsTo{
          field: ^field,
          owner_key: foreign_key,
          related_key: parent_key
        } ->
          Map.put(child, foreign_key, Map.fetch!(parent, parent_key))

        _ ->
          result
      end
    end)
  end
end
