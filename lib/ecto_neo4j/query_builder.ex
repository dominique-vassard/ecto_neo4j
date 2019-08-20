defmodule EctoNeo4j.QueryBuilder do
  import Ecto.Query
  alias EctoNeo4j.Cql.Node, as: NodeCql
  alias EctoNeo4j.Helper

  @valid_operators [:==, :in, :>, :>=, :<, :<=]
  def build(query_type, queryable_or_schema, sources, opts \\ [])

  def build(query_type, %Ecto.Query{} = query, sources, _opts) do
    {source, _schema} = query.from.source
    wheres = query.wheres

    # query
    # |> Map.from_struct()
    # |> IO.inspect()

    cql_return = build_return(query.select)

    {cql_where, params} = build_where(wheres, sources)

    cql_order_by = build_order_bys(query.order_bys)

    cql_limit = build_limit(query.limit)

    cql_skip = build_skip(query.offset)

    cql =
      NodeCql.build_query(
        query_type,
        source,
        cql_where,
        cql_return,
        cql_order_by,
        cql_limit,
        cql_skip
      )

    {cql, Helper.manage_id(params, :to_db)}
  end

  def build(query_type, schema, sources, opts) do
    query = from(s in schema)
    build(query_type, query, sources, opts)
  end

  defp build_return(%{fields: select_fields}) do
    select_fields
    |> Enum.map(&resolve_field_name/1)
    |> Enum.join(", ")
  end

  defp build_return(_) do
    "n"
  end

  defp build_limit(%Ecto.Query.QueryExpr{expr: res_limit}) do
    res_limit
  end

  defp build_limit(_) do
    nil
  end

  defp build_skip(%Ecto.Query.QueryExpr{expr: res_skip}) do
    res_skip
  end

  defp build_skip(_) do
    nil
  end

  defp resolve_field_name({{:., _, [{:&, [], [0]}, field_name]}, [], []}) do
    "n." <> format_field(field_name)
  end

  # defp build_where(%Ecto.Query.BooleanExpr{expr: expr}) do
  #   do_build_where(expr)
  # end

  defp build_where([%Ecto.Query.BooleanExpr{expr: expression, params: ecto_params}], sources) do
    {cql_where, unbound_params, _} = do_build_where(expression, sources)

    ecto_params = ecto_params || []
    # Merge unbound params and params explicitly bind in Query
    params =
      ecto_params
      |> Enum.into(%{}, fn {value, {0, field}} ->
        {field, value}
      end)
      |> Map.merge(unbound_params)

    {cql_where, params}
  end

  defp build_where([], _) do
    {"", %{}}
  end

  defp do_build_where(expression, sources, inc \\ 0)

  defp do_build_where(
         {operator, _, [_, %Ecto.Query.Tagged{type: {_, field}, value: value}]},
         _sources,
         inc
       ) do
    cql = "n.#{format_field(field)} #{format_operator(operator)} {param_#{inc}}"

    params =
      %{"param_#{inc}" => value}
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    {cql, params, inc}
  end

  # defp do_build_where(
  #        {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, {:^, _, _}]},
  #        sources,
  #        inc
  #      ) do
  #   cql = "n.#{format_field(field)} #{format_operator(operator)} {#{format_field(field)}}"
  #   {cql, %{}, inc}
  # end

  defp do_build_where(
         {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, {:^, _, [sources_index]}]},
         sources,
         inc
       ) do
    cql = "n.#{format_field(field)} #{format_operator(operator)} {#{format_field(field)}}"

    params =
      %{}
      |> Map.put(String.to_atom(format_field(field)), Enum.at(sources, sources_index))

    {cql, params, inc}
  end

  defp do_build_where(
         {operator, _,
          [{{:., _, [{:&, _, _}, field]}, [], []}, %Ecto.Query.Tagged{value: {:^, _, [0]}}]},
         sources,
         inc
       ) do
    cql = "n.#{format_field(field)} #{format_operator(operator)} {#{format_field(field)}}"

    params =
      %{}
      |> Map.put(String.to_atom(format_field(field)), List.first(sources))

    {cql, params, inc}
  end

  defp do_build_where(
         {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, {:^, _, [s_index, s_length]}]},
         sources,
         inc
       ) do
    cql = "n.#{format_field(field)} #{format_operator(operator)} {#{format_field(field)}}"

    params =
      %{}
      |> Map.put(String.to_atom(format_field(field)), Enum.slice(sources, s_index, s_length))

    {cql, params, inc}
  end

  defp do_build_where(
         {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, value]},
         _sources,
         inc
       ) do
    params =
      %{"param_#{inc}" => value}
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    cql = "n.#{format_field(field)} #{format_operator(operator)} {param_#{inc}}"
    {cql, params, inc}
  end

  defp do_build_where({operator, _, [arg]}, sources, inc) do
    {cql_sub, params, inc} = do_build_where(arg, sources, inc + 1)
    cql = "#{Atom.to_string(operator)} (#{cql_sub})"

    {cql, params, inc + 1}
  end

  defp do_build_where({operation, _, [arg1, arg2]}, sources, inc) do
    {cql1, params1, inc} = do_build_where(arg1, sources, inc + 1)
    {cql2, params2, _} = do_build_where(arg2, sources, inc + 1)

    cql = "#{cql1} #{Atom.to_string(operation)} #{cql2}"
    params = Map.merge(params1, params2)
    {cql, params, inc + 1}
  end

  defp build_order_bys([]) do
    ""
  end

  defp build_order_bys([%Ecto.Query.QueryExpr{expr: expression}]) do
    expression
    |> Enum.map(fn {order, fields} ->
      format_order_bys(fields)
      |> Enum.map(fn o -> "#{o} #{order |> Atom.to_string() |> String.upcase()}" end)
    end)
    |> List.flatten()
    |> Enum.join(", ")
  end

  defp format_order_bys(order_by_fields) when is_list(order_by_fields) do
    Enum.map(order_by_fields, &resolve_field_name/1)
  end

  defp format_order_bys(order_by_fields) do
    format_order_bys([order_by_fields])
  end

  defp format_operator(:==) do
    "="
  end

  defp format_operator(:in) do
    "IN"
  end

  defp format_operator(operator) when operator in @valid_operators do
    Atom.to_string(operator)
  end

  defp format_field(:id), do: format_field(:nodeId)
  defp format_field(field), do: field |> Atom.to_string()
end
