defmodule Ecto.Adapters.Neo4j.QueryMapper do
  @moduledoc """
  Mapper that converts an `Ecto.Query` struct into a `Ecto.Adapters.Neo4j.Query` one.
  """
  alias Ecto.Adapters.Neo4j.{Query, Condition, Helper}

  @doc """
  Map Ecto.Query to Ecto.Adapters.Neo4j.Query
  """
  @spec map(atom(), Ecto.Query.t(), list(), Keyword.t()) :: Query.t()
  def map(operation, %Ecto.Query{} = query, unbound_params, opts) do
    case is_preload?(query.select) do
      true ->
        map_preload(operation, query, unbound_params, opts)

      false ->
        map_query(operation, query, unbound_params, opts)
    end
  end

  @doc """
  Map a non-preload `Ecto.Query` to `Ecto.Adapters.Neo4j.Query`
  """
  @spec map_query(atom(), Ecto.Query.t(), [], Keyword.t()) :: Query.t()
  def map_query(operation, %Ecto.Query{} = query, unbound_params, opts) do
    neo4j_query =
      Query.new(operation)
      |> Query.batch(%Query.Batch{
        is_batch?: opts[:batch],
        type: :basic,
        chunk_size: opts[:chunk_size]
      })
      |> Query.match(map_from(query.sources))

    # Manage JOIN
    neo4j_query =
      query.joins
      |> Enum.map(&map_join(&1, unbound_params))
      |> Enum.reduce(neo4j_query, fn %{match: match, where: where, params: params}, acc ->
        acc
        |> Query.match(match)
        |> Query.where(where)
        |> Query.params(params)
      end)

    # Manage WHERE
    wheres =
      query.wheres
      |> Enum.reduce(%{params: %{}, where: nil}, fn where, clauses ->
        map_where(where, unbound_params, clauses)
      end)

    neo4j_query =
      case wheres do
        nil ->
          neo4j_query

        valid_wheres ->
          neo4j_query
          |> Query.where(valid_wheres.where)
          |> Query.params(valid_wheres.params)
      end

    # Manage SET
    sets =
      query.updates
      |> Enum.reduce(%{params: %{}, set: []}, fn update, clauses ->
        map_update(update, unbound_params, clauses)
      end)

    # MANAGE :delete_all operation
    neo4j_query =
      if operation == :delete_all do
        Query.delete(neo4j_query, neo4j_query.match)
      else
        neo4j_query
      end

    neo4j_query =
      case sets do
        nil ->
          neo4j_query

        valid_sets ->
          neo4j_query
          |> Query.set(valid_sets.set)
          |> Query.params(valid_sets.params)
      end

    return = %Query.ReturnExpr{
      distinct?: map_distinct(query.distinct),
      fields: map_select(query.select)
    }

    neo4j_query
    |> Query.return(return)
    |> Query.order_by(map_order_by(query.order_bys))
    |> Query.limit(map_limit(query.limit))
    |> Query.skip(map_offset(query.offset))
  end

  @spec is_preload?(map()) :: bool
  defp is_preload?(%Ecto.Query.SelectExpr{expr: {:{}, [], [_, {:&, [], [0]}]}, fields: [_ | _]}) do
    true
  end

  defp is_preload?(_) do
    false
  end

  @doc """
  Converts `EctoQuery.sources` into an `Ecto.Adapters.Neo4j.Query` compliant list of NodeExpr
  which would be used in `MATCH`
  """
  @spec map_from(tuple) :: [Query.NodeExpr.t()]
  def map_from(sources) when is_tuple(sources) do
    node_labels =
      sources
      |> Tuple.to_list()
      |> Enum.map(fn {label, _, _} -> label end)

    for index <- 0..(length(node_labels) - 1) do
      %Query.NodeExpr{
        index: index,
        variable: "n_" <> Integer.to_string(index),
        labels: [Enum.at(node_labels, index)]
      }
    end
  end

  @doc """
  Produce a `Neo4j.Query` to retrieve relationship (mapping of the ecto preload operation)
  """
  @spec map_preload(atom(), Ecto.Query.t(), list, Keyword.t()) :: Query.t()
  def map_preload(operation, query, unbound_params, _opts) do
    %{expr: {:{}, [], [field, {:&, [], [0]}]}, fields: _} = query.select

    %Query.FieldExpr{name: foreign_key} = format_field(field)

    {{_, schema, _}} = query.sources

    start_node_data =
      Enum.map(schema.__schema__(:associations), fn assoc ->
        schema.__schema__(:association, assoc)
      end)
      |> Enum.filter(fn
        %Ecto.Association.BelongsTo{owner_key: ^foreign_key} -> true
        _ -> false
      end)
      |> List.first()

    %{field: rel_desc, queryable: parent_schema} = start_node_data

    target_name =
      schema
      |> Module.split()
      |> List.last()
      |> String.downcase()

    rel_type =
      rel_desc
      |> Atom.to_string()
      |> String.replace("_" <> target_name, "")
      |> String.upcase()

    primary_key = parent_schema.__schema__(:primary_key) |> List.first()

    start_node = %Query.NodeExpr{
      variable: "n",
      labels: [parent_schema.__schema__(:source)]
    }

    end_node =
      query.sources
      |> map_from()
      |> List.first()

    relationship = %Query.RelationshipExpr{
      start: start_node,
      end: end_node,
      variable: "rel",
      type: rel_type
    }

    pk =
      primary_key
      |> Helper.translate_field(:to_db)
      |> Atom.to_string()

    bound_name = start_node.variable <> "_" <> pk

    condition = %Condition{
      source: start_node.variable,
      field: primary_key,
      operator: :==,
      value: bound_name
    }

    params = Map.put(%{}, String.to_atom(bound_name), Enum.at(unbound_params, 0))

    return_fields =
      map_select(query.select)
      |> Enum.reject(fn %Query.FieldExpr{name: field_name} ->
        field_name == foreign_key
      end)
      |> Kernel.++([
        %Query.FieldExpr{
          alias: foreign_key,
          name: primary_key,
          variable: "n"
        },
        %Query.FieldExpr{
          name: primary_key,
          variable: "n"
        },
        %Query.CollectExpr{
          alias: "rel_preload",
          variable: relationship.variable
        }
      ])

    Query.new(operation)
    |> Query.match([relationship])
    |> Query.where(condition)
    |> Query.return(%Query.ReturnExpr{
      fields: return_fields
    })
    |> Query.params(params)
  end

  @doc """
  Map `join` into `Neo4j.Query` compliant relationship query.

  `on` will be used to define filters.

  Note that every realtionship filters have to be specified as `on` clauses
  """
  @spec map_join(map(), map) ::
          Ecto.Adapters.Neo4j.Condition.Relationship.clauses()
  def map_join(%Ecto.Query.JoinExpr{ix: source_idx, on: %{expr: true} = on}, unbound_params) do
    build_conditions(Map.merge(on, %{source_idx: source_idx}), unbound_params)
    |> Ecto.Adapters.Neo4j.Condition.Relationship.format()
  end

  def map_join(%Ecto.Query.JoinExpr{on: on}, unbound_params) do
    build_conditions(on, unbound_params)
    |> Ecto.Adapters.Neo4j.Condition.Relationship.format()
  end

  @doc """
  Map `EctoQuery.wheres` to `Neo4j.Condition` which will used to build `WHERE` clauses.
  """
  @spec map_where([map()] | map(), map(), %{params: map, where: Condition.t()}) :: %{
          params: map,
          where: Condition.t()
        }
  def map_where(expression, unbound_params, clauses) do
    build_conditions(expression, unbound_params)
    |> Ecto.Adapters.Neo4j.Condition.Node.format(clauses)
  end

  @doc """
  Map `EctoQuery` distinct clause to a `Neo4j.Query` compliant one.
  """
  @spec map_distinct(nil | map) :: boolean
  def map_distinct(%Ecto.Query.QueryExpr{}) do
    true
  end

  def map_distinct(_) do
    false
  end

  @doc """
  Map `Ecto.Query.select` to `Neo4j.Query` list of return (nodes, relationships o fields)
  which will be used in `RETURN`
  """
  @spec map_select(nil | map) :: [
          Query.NodeExpr.t()
          | Query.RelationshipExpr.t()
          | Query.AggregateExpr.t()
        ]
  def map_select(%{fields: []}) do
    default_return()
  end

  def map_select(
        %Ecto.Query.SelectExpr{expr: {:{}, [], [_, {:&, [], [0]}]}, fields: [_ | _]} = select
      ) do
    map_select(%{expr: select.fields})
  end

  def map_select(%{expr: {:&, [], [_]}, fields: select_fields}) do
    build_return_fields(select_fields)
  end

  def map_select(%{expr: {type, [], select_fields}, fields: alt_select_fields}) do
    case type in [:%{}, :{}] do
      true -> build_return_fields(select_fields)
      _ -> build_return_fields(alt_select_fields)
    end
  end

  def map_select(%{expr: select_fields}) do
    build_return_fields(select_fields)
  end

  def map_select(nil) do
    [nil]
  end

  @spec default_return() :: [Query.NodeExpr.t()]
  defp default_return() do
    [
      %Query.NodeExpr{
        index: 0,
        variable: "n_0"
      }
    ]
  end

  @doc """
  Map `EctoQuery.order_bys` to `Neo4j.Query` compliant ones.
  """
  @spec map_order_by([map]) :: [Query.OrderExpr.t()]
  def map_order_by([]) do
    []
  end

  def map_order_by([%Ecto.Query.QueryExpr{expr: expression}]) do
    List.foldl(expression, [], fn {order, data}, acc ->
      acc ++ do_map_order(order, data)
    end)
  end

  @spec do_map_order(atom(), [] | atom()) :: [Query.OrderExpr.t()]
  defp do_map_order(order, fields) when is_list(fields) do
    List.foldl(fields, [], fn field, acc ->
      acc ++ do_map_order(order, field)
    end)
  end

  defp do_map_order(order, field) do
    [
      %Query.OrderExpr{
        order: order,
        field: format_field(field)
      }
    ]
  end

  @doc """
  Map `EctoQuery.updates` to `Neo4j.Query` list of Sets which will be used in `SET`s.§
  """
  @spec map_update(map, map, %{params: map, set: [Query.SetExpr.t()]}) :: %{
          params: map,
          set: [Query.SetExpr.t()]
        }
  def map_update(%Ecto.Query.QueryExpr{expr: [{set_type, set_data}]}, unbound_params, clauses) do
    %{set: sets, params: params} =
      set_data
      |> Enum.reduce(%{set: [], params: %{}}, fn
        {field, value}, clauses ->
          bound_name = "n_0_s_" <> Atom.to_string(field)

          set = %Query.SetExpr{
            field: %Query.FieldExpr{
              variable: "n_0",
              name: field
            },
            value: bound_name
          }

          final_set =
            case set_type do
              :inc -> Map.put(set, :increment, bound_name)
              :set -> Map.put(set, :value, bound_name)
            end

          param = Map.put(%{}, String.to_atom(bound_name), extract_value(value, unbound_params))
          %{clauses | set: clauses.set ++ [final_set], params: Map.merge(clauses.params, param)}
      end)

    %{clauses | set: clauses.set ++ sets, params: Map.merge(clauses.params, params)}
  end

  @spec extract_value(any, map()) :: any
  defp extract_value({:^, [], [param_index]}, unbound_params) do
    Enum.at(unbound_params, param_index)
  end

  defp extract_value(value, _) do
    value
  end

  @doc """
  Map `EctoQuery.limit` to `Neo4j.Query` compliant ones.
  """
  @spec map_limit(nil | map) :: nil | integer()
  def map_limit(%Ecto.Query.QueryExpr{expr: limit}) do
    limit
  end

  def map_limit(_) do
    nil
  end

  @doc """
  Map `EctoQuery.order_bys` to `Neo4j.Query` compliant value to be used in `SKIP`.
  """
  @spec map_offset(nil | map) :: nil | integer()
  def map_offset(%Ecto.Query.QueryExpr{expr: skip}) do
    skip
  end

  def map_offset(_) do
    nil
  end

  ######################################################################
  @spec build_return_fields(map | tuple) :: [Query.FieldExpr.t() | Query.AggregateExpr.t()]
  defp build_return_fields(%Ecto.Query.Tagged{value: field}) do
    [format_field(field)]
  end

  defp build_return_fields(fields) do
    fields
    |> Enum.map(&format_field/1)
  end

  @spec format_field(tuple) :: Query.FieldExpr.t() | Query.AggregateExpr.t()
  defp format_field({field_alias, {{:., _, [{:&, [], [entity_index]}, field_name]}, _, _}}) do
    %Query.FieldExpr{
      alias: format_field_alias(field_alias),
      variable: "n_" <> Integer.to_string(entity_index),
      name: Helper.translate_field(field_name, :to_db)
    }
  end

  defp format_field({{:., _, [{:&, [], [entity_index]}, field_name]}, _, _}) do
    %Query.FieldExpr{
      variable: "n_" <> Integer.to_string(entity_index),
      name: Helper.translate_field(field_name, :to_db)
    }
  end

  defp format_field({aggregate_operator, [], [field | distinct]}) do
    %Query.AggregateExpr{
      operator: aggregate_operator,
      field: format_field(field),
      distinct?: distinct == [:distinct]
    }
  end

  @spec format_field_alias(atom | String.t()) :: String.t()
  defp format_field_alias(field_alias) when is_binary(field_alias) do
    field_alias
  end

  defp format_field_alias(field_alias) when is_atom(field_alias) do
    Atom.to_string(field_alias)
  end

  @spec build_conditions(map | [map], map) :: Condition.t()
  defp build_conditions([%{expr: expression, op: join_operator}], unbound_params) do
    do_build_condition(expression, unbound_params, join_operator)
  end

  defp build_conditions([%{expr: expression}], unbound_params) do
    do_build_condition(expression, unbound_params)
  end

  defp build_conditions(%{expr: true, source_idx: source_idx}, _) do
    %Condition{
      source: "n_" <> Integer.to_string(source_idx),
      field: nil,
      operator: :==,
      value: %{}
    }
  end

  defp build_conditions(%{} = wheres, unbound_params) do
    build_conditions([wheres], unbound_params)
  end

  @spec do_build_condition(tuple, map, atom) :: Condition.t()
  defp do_build_condition(expression, unbound_params, join_operator \\ :and)

  defp do_build_condition(
         {operator, _, [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}, {:^, _, [param_index]}]},
         sources,
         join_operator
       ) do
    %Condition{
      source: "n_" <> Integer.to_string(node_idx),
      field: field,
      operator: operator,
      value: Enum.at(sources, param_index),
      conditions: [],
      join_operator: join_operator
    }
  end

  defp do_build_condition(
         {operator, _,
          [
            {{:., _, [{:&, _, [node_idx]}, field]}, [], []},
            %Ecto.Query.Tagged{value: {:^, _, [param_index]}}
          ]},
         sources,
         join_operator
       ) do
    %Condition{
      source: "n_" <> Integer.to_string(node_idx),
      field: field,
      operator: operator,
      value: Enum.at(sources, param_index),
      conditions: [],
      join_operator: join_operator
    }
  end

  defp do_build_condition(
         {operator, _,
          [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}, {:^, _, [param_index, param_length]}]},
         unbound_params,
         join_operator
       ) do
    %Condition{
      source: "n_" <> Integer.to_string(node_idx),
      field: field,
      operator: operator,
      value: Enum.slice(unbound_params, param_index, param_length),
      conditions: [],
      join_operator: join_operator
    }
  end

  defp do_build_condition(
         {operator, _, [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}, value]},
         _unbound_params,
         join_operator
       ) do
    %Condition{
      source: "n_" <> Integer.to_string(node_idx),
      field: field,
      operator: operator,
      value: value,
      conditions: [],
      join_operator: join_operator
    }
  end

  defp do_build_condition(
         {operator, _, [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}]},
         _unbound_params,
         join_operator
       ) do
    %Condition{
      source: "n_" <> Integer.to_string(node_idx),
      field: field,
      operator: operator,
      value: :no_value,
      conditions: [],
      join_operator: join_operator
    }
  end

  defp do_build_condition({operator, _, [arg]}, unbound_params, join_operator) do
    %Condition{
      operator: operator,
      conditions: do_build_condition(arg, unbound_params, :and),
      join_operator: join_operator
    }
  end

  defp do_build_condition({operator, _, [arg1, arg2]}, unbound_params, join_operator) do
    %Condition{
      operator: operator,
      conditions: [
        do_build_condition(arg1, unbound_params),
        do_build_condition(arg2, unbound_params)
      ],
      join_operator: join_operator
    }
  end
end
