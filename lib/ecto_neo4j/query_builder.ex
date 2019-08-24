defmodule EctoNeo4j.QueryBuilder do
  import Ecto.Query
  alias EctoNeo4j.Cql.Node, as: NodeCql
  alias EctoNeo4j.Helper

  @valid_operators [:==, :in, :>, :>=, :<, :<, :min, :max, :count, :sum, :avg]
  def build(query_type, queryable_or_schema, sources, opts \\ [])

  def build(query_type, %Ecto.Query{} = query, sources, _opts) do
    {source, _schema} = query.from.source
    wheres = query.wheres

    # query
    # |> Map.from_struct()
    # |> IO.inspect()

    {cql_update, update_params} = build_update(query.updates, sources)

    {cql_where, where_params} = build_where(wheres, sources)

    cql_return = build_return(query.select)

    cql_order_by = build_order_bys(query.order_bys)

    cql_limit = build_limit(query.limit)

    cql_skip = build_skip(query.offset)

    cql =
      NodeCql.build_query(
        query_type,
        source,
        cql_where,
        cql_update,
        cql_return,
        cql_order_by,
        cql_limit,
        cql_skip
      )

    params = Map.merge(update_params, where_params)

    {cql, Helper.manage_id(params, :to_db)}
  end

  def build(query_type, schema, sources, opts) do
    query = from(s in schema)
    build(query_type, query, sources, opts)
  end

  defp build_return(%{fields: []}) do
    "n"
  end

  defp build_return(%{fields: select_fields}) do
    select_fields
    # |> Enum.map(&resolve_field_name/1)
    |> Enum.map(&format_return_field/1)
    |> Enum.join(", ")
  end

  defp build_return(_) do
    "n"
  end

  defp format_return_field({aggregate, [], [field]}) do
    format_operator(aggregate) <> "(" <> resolve_field_name(field) <> ")"
  end

  defp format_return_field(field) do
    resolve_field_name(field)
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

  defp build_where([_ | _] = wheres, sources) do
    {cqls, params} =
      wheres
      |> Enum.map(&build_where(&1, sources))
      |> Enum.reduce({[], %{}}, fn {sub_cql, sub_param}, {cql, params} ->
        {cql ++ [sub_cql], Map.merge(params, sub_param)}
      end)

    # We have to use the operator of the BooleanExpr, not the one inside the expression
    # Because there is as many operators as sub query, we tkae only the last 2 operators
    # to build the final query
    cql =
      Enum.map(wheres, fn %Ecto.Query.BooleanExpr{op: operator} ->
        operator
        |> Atom.to_string()
        |> String.upcase()
      end)
      |> List.delete_at(0)
      |> Kernel.++([""])
      |> Enum.zip(cqls)
      |> Enum.reduce("", fn {sub_cql, operator}, cql ->
        cql <> " " <> operator <> " " <> sub_cql
      end)

    {cql, params}
  end

  defp build_where(%Ecto.Query.BooleanExpr{} = wheres, sources) do
    build_where([wheres], sources)
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

  defp do_build_where({operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}]}, _sources, inc) do
    cql = "n.#{format_field(field)} #{format_operator(operator)}"
    {cql, %{}, inc}
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

  defp build_update([%Ecto.Query.QueryExpr{expr: expression}], sources) do
    {data, inc} = do_build_update_data(:set, Keyword.get(expression, :set, []), sources)

    {data, _} = do_build_update_data(:inc, Keyword.get(expression, :inc, []), sources, inc, data)

    {cqls, params} =
      Enum.reduce(data, {[], %{}}, fn {sub_cql, sub_params}, {cqls, params} ->
        {cqls ++ [sub_cql], Map.merge(params, sub_params)}
      end)

    {Enum.join(cqls, ", "), params}
  end

  defp build_update([], _) do
    {"", %{}}
  end

  defp do_build_update_data(update_type, expression, sources, inc \\ 0, result \\ [])

  defp do_build_update_data(
         update_type,
         [{field, {:^, [], [sources_idx]}} | tail],
         sources,
         inc,
         result
       ) do
    cql = build_update_cql(update_type, Atom.to_string(field), inc)
    params = %{"param_up#{inc}" => Enum.at(sources, sources_idx)}

    do_build_update_data(update_type, tail, sources, inc + 1, result ++ [{cql, params}])
  end

  defp do_build_update_data(_, [], _, inc, result) do
    {result, inc}
  end

  defp build_update_cql(:set, field, inc) do
    "n.#{field} = {param_up#{inc}}"
  end

  defp build_update_cql(:inc, field, inc) do
    "n.#{field} = n.#{field} + {param_up#{inc}}"
  end

  # defp do_build_update_data(expression, sources, inc \\ 0, result \\ []) do
  #   {cqls, params} =
  #     expression
  #     |> Enum.reduce([], fn {field, {:^, [], [sources_idx]}}, acc ->
  #       cql = "n.#{Atom.to_string(field)} = {param_#{inc}}"
  #       params = %{"param_#{inc}" => Enum.at(sources, sources_idx)}
  #       acc ++ [{cql, params}]
  #     end)
  #     |> IO.inspect()
  #     |> Enum.reduce({[], %{}}, fn {sub_cql, sub_params}, {cqls, params} ->
  #       {cqls ++ sub_cql, Map.merge(params, sub_params)}
  #     end)

  #   # {[Enum.join(cqls, ", ")], params}
  # end

  # defp do_build_update_data(nil, _, inc) do
  #   {[], %{}, inc}
  # end

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

  defp format_operator(:!=) do
    "<>"
  end

  defp format_operator(:in) do
    "IN"
  end

  defp format_operator(:is_nil) do
    "IS NULL"
  end

  defp format_operator(operator) when operator in @valid_operators do
    Atom.to_string(operator)
  end

  defp format_field(:id), do: format_field(:nodeId)
  defp format_field(field), do: field |> Atom.to_string()
end
