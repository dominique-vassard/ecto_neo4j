defmodule Ecto.Adapters.Neo4j.QueryMapper do
  alias Ecto.Adapters.Neo4j.{Query, Condition, Helper}

  @spec map(atom(), Ecto.Query.t(), []) :: Ecto.Adapters.Neo4j.Query.t()
  def map(operation, %Ecto.Query{} = query, unbound_params) do
    neo4j_query =
      Query.new(operation)
      |> Query.match(map_from(query.sources))

    # Manage JOIN
    # neo4j_query =
    #   query.joins
    #   |> Enum.map(&map_join(&1, unbound_params))
    #   |> Enum.reduce(neo4j_query, fn %{match: match, where: where, params: params}, acc ->
    #     acc
    #     |> Query.match(match)
    #     |> Query.where(where)
    #     |> Query.params(params)
    #   end)

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
      is_distinct?: map_distinct(query.distinct),
      fields: map_select(query.select)
    }

    neo4j_query
    |> Query.return(return)
    |> Query.order_by(map_order_by(query.order_bys))
    |> Query.limit(map_limit(query.limit))
    |> Query.skip(map_offset(query.offset))
  end

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

  def map_join(%Ecto.Query.JoinExpr{on: on}, unbound_params) do
    build_conditions(on, unbound_params)
    |> Ecto.Adapters.Neo4j.Condition.Relationship.format()
  end

  def map_where(expression, unbound_params, clauses) do
    build_conditions(expression, unbound_params)
    |> Ecto.Adapters.Neo4j.Condition.Node.format(clauses)
  end

  def map_distinct(%Ecto.Query.QueryExpr{}) do
    true
  end

  def map_distinct(_) do
    false
  end

  def map_select(%{fields: []}) do
    default_return()
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

  defp default_return() do
    [
      %Query.NodeExpr{
        index: 0,
        variable: "n_0"
      }
    ]
  end

  def map_order_by([]) do
    []
  end

  def map_order_by([%Ecto.Query.QueryExpr{expr: expression}]) do
    List.foldl(expression, [], fn {order, data}, acc ->
      acc ++ do_map_order(order, data)
    end)
  end

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

  defp extract_value({:^, [], [param_index]}, unbound_params) do
    Enum.at(unbound_params, param_index)
  end

  defp extract_value(value, _) do
    value
  end

  @spec map_limit(nil | Ecto.Query.QueryExpr.t()) :: nil | integer()
  def map_limit(%Ecto.Query.QueryExpr{expr: limit}) do
    limit
  end

  def map_limit(_) do
    nil
  end

  @spec map_offset(nil | Ecto.Query.QueryExpr.t()) :: nil | integer()
  def map_offset(%Ecto.Query.QueryExpr{expr: skip}) do
    skip
  end

  def map_offset(_) do
    nil
  end

  ######################################################################
  defp build_return_fields(%Ecto.Query.Tagged{value: field}) do
    format_field(field)
  end

  defp build_return_fields(fields) do
    fields
    |> Enum.map(&format_field/1)
  end

  # defp format_return_field({{:., _, [{:&, [], [entity_index]}, field_name]}, _, _}) do
  #   %Query.FieldExpr{
  #     variable: "n_" <> Integer.to_string(entity_index),
  #     name: Helper.translate_field(field_name, :to_db)
  #   }
  # end

  defp format_field({field_alias, {{:., _, [{:&, [], [entity_index]}, field_name]}, _, _}}) do
    %Query.FieldExpr{
      alias:
        if is_binary(field_alias) do
          field_alias
        else
          Atom.to_string(field_alias)
        end,
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
      is_distinct?: distinct == [:distinct]
    }
  end

  defp build_conditions([%{expr: expression, op: join_operator}], unbound_params) do
    do_build_condition(expression, unbound_params, join_operator)
  end

  defp build_conditions(%{} = wheres, unbound_params) do
    build_conditions([wheres], unbound_params)
  end

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
      conditions: do_build_condition(arg, :and, unbound_params),
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
