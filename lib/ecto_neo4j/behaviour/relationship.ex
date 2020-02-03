defmodule Ecto.Adapters.Neo4j.Behaviour.Relationship do
  @moduledoc """
  Manage relationship operations
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

  @spec do_process_relationships(Ecto.Schema.t() | map()) :: :ok
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

  @spec manage_assoc(Ecto.Schema.t(), atom(), map() | list(map())) :: :ok
  defp manage_assoc(_data, _assoc, %Ecto.Association.NotLoaded{}) do
    :ok
  end

  defp manage_assoc(data, assoc, data_assoc) when is_list(data_assoc) do
    Enum.each(data_assoc, fn d_assoc ->
      {relationship, %{where: where, params: params}} =
        build_relationship_and_clauses(data, d_assoc, assoc)

      %{__struct__: child_schema} = d_assoc
      %{__struct__: parent_schema} = data
      rel_type = extract_relationship_type(assoc, parent_schema, child_schema)

      rel_data = Map.fetch!(d_assoc, String.to_atom("rel_" <> String.downcase(rel_type)))
      %{sets: sets, params: set_params} = build_set(rel_data, relationship, assoc)

      merge_rel =
        relationship
        |> Map.put(:start, Map.drop(relationship.start, [:labels]))
        |> Map.put(:end, Map.drop(relationship.end, [:labels]))

      merge = %Query.MergeExpr{
        expr: merge_rel,
        on_create: sets
      }

      {cql, params} =
        Query.new(:create)
        |> Query.match([relationship.start, relationship.end])
        |> Query.where(where)
        |> Query.merge([merge])
        |> Query.params(Map.merge(params, set_params))
        |> Query.to_string()

      Ecto.Adapters.Neo4j.query!(cql, params)
    end)
  end

  defp manage_assoc(data, assoc, data_assoc) do
    manage_assoc(data, assoc, [data_assoc])
  end

  @doc """
  Remove / add relationship.

  For this to work, `has_one`, `has_many`, `belongs_to` declaration must have the option `on_replace: :delete`.

  `:update` will add a new relationship (without its data, they will be added later during the update process)
  `:replace` will remove the relationship

  This function should not be called directly but through `Ecto.Adapters.Neo4j.update/3`

  ## Example
      user = MyRepo.get!(User, user_uuid)
      post = MyRepo.get!(Post, post_uuid)

      # This will set the relationship (User)-[:WROTE]->(Post)
      update(:update, user, post, :wrote_post)

      # This will remove the relationship (User)-[:WROTE]->(Post)
      update(:delete, user, post, :wrote_post)
  """
  @spec update(Ecto.Changeset.t(), Ecto.Schema.t(), atom()) :: nil | Ecto.Schema.t()
  def update(
        %Ecto.Changeset{action: :update, data: node2_data, changes: rel_data} = changeset,
        node1_data,
        rel_name
      ) do
    {relationship_data, %{where: where, params: params}} =
      build_relationship_and_clauses(node1_data, node2_data, rel_name)

    %{__struct__: node1_schema} = node1_data

    {optional_match, delete} =
      case node1_schema.__schema__(:association, rel_name) do
        %Ecto.Association.BelongsTo{cardinality: :one} ->
          rel_old =
            relationship_data
            |> Map.put(:start, Map.drop(relationship_data.start, [:variable]))
            |> Map.put(:end, Map.drop(relationship_data.end, [:labels]))
            |> Map.put(:variable, "rel_old")

          {[rel_old], [rel_old]}

        %Ecto.Association.Has{cardinality: :one} ->
          rel_old =
            relationship_data
            |> Map.put(:start, Map.drop(relationship_data.start, [:labels]))
            |> Map.put(:end, Map.drop(relationship_data.end, [:variable]))
            |> Map.put(:variable, "rel_old")

          {[rel_old], [rel_old]}

        _ ->
          {[], []}
      end

    # Manage relationship data
    rel_key =
      ("rel_" <> String.downcase(relationship_data.type))
      |> String.to_atom()

    %{params: set_params, sets: sets} =
      if Kernel.match?(%Ecto.Association.Has{}, node1_schema.__schema__(:association, rel_name)) and
           Map.get(rel_data, rel_key) do
        build_set(Map.get(rel_data, rel_key), relationship_data, rel_name)
      else
        %{params: %{}, sets: []}
      end

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
      |> Query.optional_match(optional_match)
      |> Query.delete(delete)
      |> Query.merge([
        %Query.MergeExpr{
          expr: relationship
        }
      ])
      |> Query.set(sets)
      |> Query.where(where)
      |> Query.params(Map.merge(params, set_params))
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)

    add_fk_data(node1_data, Ecto.Changeset.apply_changes(changeset), rel_name)
  end

  def update(%Ecto.Changeset{action: :replace, data: node2_data}, node1_data, rel_name) do
    # def update(:replace, node1_data, node2_data, rel_name, _) do
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

  def delete(node_data, rel_name) do
    node_info = node_info(node_data)

    %{__struct__: schema} = node_data

    {queryable, node_start, node_end} =
      case schema.__schema__(:association, rel_name) do
        %Ecto.Association.BelongsTo{queryable: queryable} ->
          node_start = %Query.NodeExpr{
            labels: [queryable.__schema__(:source)]
          }

          {queryable, node_start, node_info.expr}

        %Ecto.Association.Has{queryable: queryable} ->
          node_end = %Query.NodeExpr{
            labels: [queryable.__schema__(:source)]
          }

          {queryable, node_info.expr, node_end}
      end

    relationship = %Query.RelationshipExpr{
      start: node_start,
      end: node_end,
      variable: "rel",
      type: extract_relationship_type(rel_name, queryable, schema)
    }

    clause =
      node_info
      |> build_where()
      |> List.first()

    {cql, params} =
      Query.new(:delete)
      |> Query.match([relationship])
      |> Query.delete([relationship])
      |> Query.where(clause.condition)
      |> Query.params(clause.params)
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)
    nil
  end

  @doc """
  Update relationship data.

  This function should not be called directly but through `Ecto.Adapters.Neo4j.update/3`
  """
  @spec update_data(atom, atom(), map(), Ecto.Schema.t()) :: Bolt.Sips.Response.t()
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

        %{sets: sets, params: set_params} = build_set(changes, relationship, assoc)

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

  @spec build_relationship_and_clauses(Ecto.Schema.t(), atom | Ecto.Schema.t(), atom()) ::
          {Query.RelationshipExpr.t(), map}
  defp build_relationship_and_clauses(node1_data, node2_data, rel_name) do
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

  @spec extract_relationship_type(atom(), atom(), atom()) :: String.t()
  defp extract_relationship_type(rel_name, queryable, node_schema) do
    str_rel_name = Atom.to_string(rel_name)

    to_replace =
      if String.ends_with?(str_rel_name, String.downcase(queryable.__schema__(:source))) do
        String.downcase(queryable.__schema__(:source))
      else
        String.downcase(node_schema.__schema__(:source))
      end

    str_rel_name
    |> String.replace("_" <> to_replace, "")
    |> String.upcase()
  end

  @spec node_info(Ecto.Schema.t()) :: map()
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

  @spec build_where(map()) :: [map()]
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

  @spec build_set(map(), Query.RelationshipExpr.t(), atom) :: map
  defp build_set(changes, %Query.RelationshipExpr{variable: rel_variable}, assoc_field) do
    Enum.reduce(changes, %{sets: [], params: %{}}, fn {field, value}, sets_data ->
      bound_name =
        rel_variable <> "_" <> Atom.to_string(assoc_field) <> "_" <> Atom.to_string(field)

      set = %Query.SetExpr{
        field: %Query.FieldExpr{
          variable: rel_variable,
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
  end

  @spec add_fk_data(Ecto.Schema.t(), Ecto.Schema.t(), atom) :: nil | Ecto.Schema.t()
  defp add_fk_data(parent, child, field) do
    %{__struct__: child_schema} = child

    case child_schema.__schema__(:association, field) do
      %Ecto.Association.BelongsTo{
        field: ^field,
        owner_key: foreign_key,
        related_key: parent_key
      } ->
        Map.put(child, foreign_key, Map.fetch!(parent, parent_key))

      _ ->
        child
    end
  end
end
