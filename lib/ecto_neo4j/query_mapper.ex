defmodule Ecto.Adapters.Neo4j.QueryMapper do
  alias Ecto.Adapters.Neo4j.{Query, Condition}

  def map(%Ecto.Query{} = query, unbound_params) do
    neo4j_query =
      Query.new()
      |> Query.match(map_from(query.sources))

    neo4j_query =
      query.joins
      |> Enum.map(&map_join(&1, unbound_params))
      |> Enum.reduce(neo4j_query, fn %{match: match, where: where, params: params}, acc ->
        acc
        |> Query.match(match)
        |> Query.where(where)
        |> Query.params(params)
      end)

    return = %Query.ReturnExpr{
      is_distinct?: map_distinct(query.distinct),
      fields: map_select(query.select)
    }

    neo4j_query
    |> Query.return(return)
    |> IO.inspect()
    |> Query.to_string()
    |> IO.inspect(pretty: true)
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
    |> Condition.to_relationship_format()
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

  def map_select(%{expr: select_fields}) do
    build_return_fields(select_fields)
  end

  def map_select(_) do
    default_return()
  end

  defp default_return() do
    %Query.NodeExpr{
      index: 0,
      variable: "n_0"
    }
  end

  ######################################################################
  defp build_return_fields(%Ecto.Query.Tagged{value: field}) do
    format_return_field(field)
  end

  defp build_return_fields(fields) do
    fields
    |> Enum.map(&format_return_field/1)
  end

  defp format_return_field({{:., _, [{:&, [], [entity_index]}, field_name]}, _, _}) do
    %Query.FieldExpr{
      variable: "n_" <> Integer.to_string(entity_index),
      name: field_name
    }
  end

  defp build_conditions([%{expr: expression}], unbound_params) do
    do_build_condition(expression, unbound_params)
  end

  defp build_conditions(%{} = wheres, unbound_params) do
    build_conditions([wheres], unbound_params)
  end

  defp do_build_condition(
         {operator, _, [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}, {:^, _, [param_index]}]},
         sources
       ) do
    %Condition{
      source: node_idx,
      field: field,
      operator: operator,
      value: Enum.at(sources, param_index),
      conditions: []
    }
  end

  defp do_build_condition(
         {operator, _,
          [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}, {:^, _, [param_index, param_length]}]},
         unbound_params
       ) do
    %Condition{
      source: node_idx,
      field: field,
      operator: operator,
      value: Enum.slice(unbound_params, param_index, param_length),
      conditions: []
    }
  end

  defp do_build_condition(
         {operator, _, [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}, value]},
         _unbound_params
       ) do
    %Condition{
      source: node_idx,
      field: field,
      operator: operator,
      value: value,
      conditions: []
    }
  end

  defp do_build_condition(
         {operator, _, [{{:., _, [{:&, _, [node_idx]}, field]}, [], []}]},
         _unbound_params
       ) do
    %Condition{
      source: node_idx,
      field: field,
      operator: operator,
      value: :no_value,
      conditions: []
    }
  end

  defp do_build_condition({operator, _, [arg]}, unbound_params) do
    %Condition{
      operator: operator,
      conditions: do_build_condition(arg, unbound_params)
    }
  end

  defp do_build_condition({operator, _, [arg1, arg2]}, unbound_params) do
    %Condition{
      operator: operator,
      conditions: [
        do_build_condition(arg1, unbound_params),
        do_build_condition(arg2, unbound_params)
      ]
    }
  end
end
